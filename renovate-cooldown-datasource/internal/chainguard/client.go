package chainguard

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"os"

	delegate "chainguard.dev/go-grpc-kit/pkg/options"
	common "chainguard.dev/sdk/proto/platform/common/v1"
	iam "chainguard.dev/sdk/proto/platform/iam/v1"
	registry "chainguard.dev/sdk/proto/platform/registry/v1"
	"chainguard.dev/sdk/sts"
	"golang.org/x/oauth2"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/oauth"
)

const (
	apiURL   = "https://console-api.enforce.dev"
	audience = apiURL
	issuer   = "https://issuer.enforce.dev"
)

// ErrRepoNotFound is returned by ListTags when the requested repo doesn't
// exist within the configured org.
var ErrRepoNotFound = errors.New("repo not found")

type authMode int

const (
	authChainctl authMode = iota
	authIdentity
)

type Client struct {
	OrgUIDP   string
	iam       iam.Clients
	registry  registry.Clients
	conn      *grpc.ClientConn
	mode      authMode
	tokenFile string // path to OIDC token file, if identity-mode + file-based
}

// New creates a Client scoped to a single Chainguard org. orgName is resolved
// to its group UIDP at construction time and all subsequent calls are scoped
// under it.
//
// The returned client uses a refreshing oauth2.TokenSource for both auth
// modes: tokens are re-read from disk (chainctl cache or projected OIDC
// token file) and re-exchanged with STS (identity mode) automatically when
// the cached Chainguard token expires. There is no need to restart the
// process when tokens rotate.
func New(ctx context.Context, orgName string, opts ...Option) (*Client, error) {
	if orgName == "" {
		return nil, errors.New("orgName is required")
	}
	o := options{
		mode: authChainctl,
	}
	for _, fn := range opts {
		fn(&o)
	}

	switch o.mode {
	case authChainctl:
		// Fail fast at startup with an actionable message.
		if _, err := loadChainctlToken(); err != nil {
			return nil, err
		}
		ts := oauth2.ReuseTokenSource(nil, &chainctlTokenSource{})
		return buildClient(ctx, orgName, ts, authChainctl, "")

	case authIdentity:
		if o.identity == "" || o.identityToken == "" {
			return nil, errors.New("WithIdentity requires both identity UIDP and token")
		}
		base, tokenFile, err := buildBaseTokenSource(o.identityToken)
		if err != nil {
			return nil, err
		}
		xchg := sts.New(issuer, audience, sts.WithIdentity(o.identity))
		ts := oauth2.ReuseTokenSource(nil, sts.NewContextTokenSource(ctx, base, xchg))
		return buildClient(ctx, orgName, ts, authIdentity, tokenFile)

	default:
		return nil, fmt.Errorf("unsupported auth mode: %d", o.mode)
	}
}

// buildClient is the shared construction path: one gRPC connection, dynamic
// per-RPC credentials sourced from the oauth2.TokenSource, IAM + Registry
// clients built from that connection.
func buildClient(ctx context.Context, orgName string, ts oauth2.TokenSource, mode authMode, tokenFile string) (*Client, error) {
	uri, err := url.Parse(apiURL)
	if err != nil {
		return nil, fmt.Errorf("invalid API URL: %w", err)
	}
	target, dialOpts := delegate.GRPCOptions(*uri)
	dialOpts = append(dialOpts, grpc.WithPerRPCCredentials(oauth.TokenSource{TokenSource: ts}))

	conn, err := grpc.NewClient(target, dialOpts...)
	if err != nil {
		return nil, fmt.Errorf("dialing %s: %w", target, err)
	}

	iamc := iam.NewClientsFromConnection(conn)
	regc := registry.NewClientsFromConnection(conn)

	orgUIDP, err := resolveOrgUIDP(ctx, iamc, orgName)
	if err != nil {
		_ = conn.Close()
		return nil, err
	}

	return &Client{
		OrgUIDP:   orgUIDP,
		iam:       iamc,
		registry:  regc,
		conn:      conn,
		mode:      mode,
		tokenFile: tokenFile,
	}, nil
}

func (c *Client) Close() error {
	errs := []error{c.iam.Close(), c.registry.Close()}
	if c.conn != nil {
		errs = append(errs, c.conn.Close())
	}
	return errors.Join(errs...)
}

// Ready reports whether the credential material is currently available.
//
// For chainctl mode this re-reads the on-disk token cache; if the operator
// has run `chainctl auth login` since startup, this will see the fresh token
// and so will the gRPC client (which re-calls TokenSource.Token on expiry).
//
// For identity mode it stats the OIDC token file if file-based; for literal
// tokens it returns nil — there's no async credential we can probe without
// making a request.
func (c *Client) Ready(_ context.Context) error {
	switch c.mode {
	case authChainctl:
		_, err := loadChainctlToken()
		return err
	case authIdentity:
		if c.tokenFile == "" {
			return nil
		}
		if _, err := os.Stat(c.tokenFile); err != nil {
			return fmt.Errorf("identity token file unreadable: %w", err)
		}
		return nil
	default:
		return fmt.Errorf("unknown auth mode")
	}
}

func resolveOrgUIDP(ctx context.Context, iamc iam.Clients, orgName string) (string, error) {
	resp, err := iamc.Groups().List(ctx, &iam.GroupFilter{Name: orgName})
	if err != nil {
		return "", fmt.Errorf("listing groups for %q: %w", orgName, err)
	}
	switch len(resp.GetItems()) {
	case 0:
		return "", fmt.Errorf("no Chainguard org found with name %q", orgName)
	case 1:
		return resp.GetItems()[0].GetId(), nil
	default:
		return "", fmt.Errorf("multiple Chainguard orgs match %q; configure with a more specific name", orgName)
	}
}

func (c *Client) resolveRepoUIDP(ctx context.Context, repoName string) (string, error) {
	resp, err := c.registry.Registry().ListRepos(ctx, &registry.RepoFilter{
		Uidp: &common.UIDPFilter{ChildrenOf: c.OrgUIDP},
		Name: repoName,
	})
	if err != nil {
		return "", fmt.Errorf("listing repos: %w", err)
	}
	items := resp.GetItems()
	if len(items) == 0 {
		return "", fmt.Errorf("%w: %s", ErrRepoNotFound, repoName)
	}
	return items[0].GetId(), nil
}

// ListTags returns the current tags for repoName within the configured org.
// Referrer (`sha256-*`) tags are filtered out by the upstream API.
func (c *Client) ListTags(ctx context.Context, repoName string) ([]Tag, error) {
	repoUIDP, err := c.resolveRepoUIDP(ctx, repoName)
	if err != nil {
		return nil, err
	}
	resp, err := c.registry.Registry().ListTags(ctx, &registry.TagFilter{
		Uidp:             &common.UIDPFilter{ChildrenOf: repoUIDP},
		ExcludeReferrers: true,
	})
	if err != nil {
		return nil, fmt.Errorf("listing tags: %w", err)
	}

	out := make([]Tag, 0, len(resp.GetItems()))
	for _, t := range resp.GetItems() {
		out = append(out, Tag{
			ID:          t.GetId(),
			Name:        t.GetName(),
			LastUpdated: t.GetLastUpdated().AsTime(),
			Digest:      t.GetDigest(),
		})
	}
	return out, nil
}

// ListTagHistory returns historical iterations of the tag identified by tagID
// (the UIDP returned in Tag.ID).
func (c *Client) ListTagHistory(ctx context.Context, tagID string) ([]TagHistory, error) {
	if tagID == "" {
		return nil, fmt.Errorf("ListTagHistory: empty tag ID")
	}
	resp, err := c.registry.Registry().ListTagHistory(ctx, &registry.TagHistoryFilter{
		ParentId: tagID,
	})
	if err != nil {
		return nil, fmt.Errorf("listing tag history for %s: %w", tagID, err)
	}
	out := make([]TagHistory, 0, len(resp.GetItems()))
	for _, h := range resp.GetItems() {
		out = append(out, TagHistory{
			UpdateTimestamp: h.GetUpdateTimestamp().AsTime(),
			Digest:          h.GetDigest(),
		})
	}
	return out, nil
}
