package oci

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/google/go-containerregistry/pkg/authn"
	"github.com/google/go-containerregistry/pkg/name"
	v1 "github.com/google/go-containerregistry/pkg/v1"
	"github.com/google/go-containerregistry/pkg/v1/remote"
	"golang.org/x/sync/errgroup"

	cosignremote "github.com/sigstore/cosign/v3/pkg/oci/remote"
	spdx "github.com/spdx/tools-golang/spdx/v2/v2_3"
)

// ErrNoSBOM is returned by SBOMSPDX when the image exists on cgr.dev but has
// no SPDX attestation we can decode. Clients can errors.Is against it to give
// a more specific response code than the generic upstream-error case.
var ErrNoSBOM = errors.New("no SPDX SBOM attestation")

// Fetcher pulls OCI configs and SBOMs from cgr.dev for repos in a single
// Chainguard org.
type Fetcher struct {
	orgName  string
	kc       authn.Keychain
	platform v1.Platform
}

// New constructs a Fetcher scoped to orgName. kc must authorise requests to
// cgr.dev (see Keychain).
func New(orgName string, kc authn.Keychain) *Fetcher {
	return &Fetcher{
		orgName:  orgName,
		kc:       kc,
		platform: v1.Platform{OS: "linux", Architecture: "amd64"},
	}
}

// ResolveDigest resolves repo @ ref to a per-platform manifest digest. Both
// tags and digests are passed through remote.Image with WithPlatform so that
// an index reference — whether named by tag or by its index-level digest —
// descends to a single-arch child manifest. Returning the index digest as-is
// would cause SBOMSPDX to fetch the index-level attestation, which only
// enumerates the child manifests rather than the apk packages we want.
func (f *Fetcher) ResolveDigest(ctx context.Context, repo, ref string) (string, error) {
	r, err := f.refFor(repo, ref)
	if err != nil {
		return "", err
	}
	img, err := remote.Image(r, append(f.remoteOpts(ctx), remote.WithPlatform(f.platform))...)
	if err != nil {
		return "", fmt.Errorf("fetching %s: %w", r, err)
	}
	d, err := img.Digest()
	if err != nil {
		return "", err
	}
	return d.String(), nil
}

// Config fetches the OCI image config for repo @ ref at the configured
// platform. Callers typically pass a digest returned by ResolveDigest, in
// which case the platform negotiation is a no-op.
func (f *Fetcher) Config(ctx context.Context, repo, ref string) (*v1.ConfigFile, error) {
	r, err := f.refFor(repo, ref)
	if err != nil {
		return nil, err
	}
	img, err := remote.Image(r, append(f.remoteOpts(ctx), remote.WithPlatform(f.platform))...)
	if err != nil {
		return nil, fmt.Errorf("fetching %s: %w", r, err)
	}
	cf, err := img.ConfigFile()
	if err != nil {
		return nil, fmt.Errorf("config %s: %w", r, err)
	}
	return cf, nil
}

// SBOMSPDX fetches the SPDX SBOM attestation attached to repo @ ref and
// returns the parsed SPDX document. Translation into the diff-friendly view
// is the caller's responsibility — this package stops at the SPDX boundary.
//
// ref must be a per-platform digest ("sha256:..."); call ResolveDigest first
// to obtain one from a tag. Passing a tag would let cosign descend into the
// index manifest and pick up the index-level signature set rather than the
// per-arch SBOMs Chainguard publishes.
func (f *Fetcher) SBOMSPDX(ctx context.Context, repo, ref string) (*spdx.Document, error) {
	r, err := f.refFor(repo, ref)
	if err != nil {
		return nil, err
	}

	se, err := cosignremote.SignedEntity(r, cosignremote.WithRemoteOptions(f.remoteOpts(ctx)...))
	if err != nil {
		return nil, fmt.Errorf("SignedEntity %s: %w", r, err)
	}
	atts, err := se.Attestations()
	if err != nil {
		return nil, fmt.Errorf("attestations %s: %w", r, err)
	}
	sigs, err := atts.Get()
	if err != nil {
		return nil, fmt.Errorf("getting attestations %s: %w", r, err)
	}

	// Attestation layers are independent fetches; doing them in parallel
	// cuts SBOM latency materially when SPDX isn't the first attestation
	// (Chainguard images typically attach 3–4 — SBOM, SLSA, VEX, scan).
	//
	// We retain egCtx so a failure in one goroutine, or a cancelled caller
	// context, short-circuits the remaining goroutines before they start
	// their Payload fetch. cosign's oci.Signature.Payload doesn't accept a
	// context itself, so the cancellation only takes effect at goroutine
	// entry — that's still better than the previous "always wait for
	// everything to finish on its own" behaviour.
	results := make([]*spdx.Document, len(sigs))
	eg, egCtx := errgroup.WithContext(ctx)
	for i, sig := range sigs {
		eg.Go(func() error {
			if err := egCtx.Err(); err != nil {
				return err
			}
			doc, ok, err := decodeSPDXFromAttestation(sig)
			if err != nil {
				return err
			}
			if ok {
				results[i] = doc
			}
			return nil
		})
	}
	if err := eg.Wait(); err != nil {
		return nil, err
	}
	for _, doc := range results {
		if doc != nil {
			return doc, nil
		}
	}
	return nil, fmt.Errorf("%w for %s", ErrNoSBOM, r)
}

func (f *Fetcher) refFor(repo, ref string) (name.Reference, error) {
	base := "cgr.dev/" + f.orgName + "/" + repo
	if strings.HasPrefix(ref, "sha256:") {
		return name.NewDigest(base + "@" + ref)
	}
	return name.NewTag(base + ":" + ref)
}

func (f *Fetcher) remoteOpts(ctx context.Context) []remote.Option {
	return []remote.Option{
		remote.WithAuthFromKeychain(f.kc),
		remote.WithContext(ctx),
	}
}

// --- attestation decoding ---

// decodeSPDXFromAttestation inspects a single cosign attestation, decodes its
// DSSE envelope, and — if the wrapped statement is an SPDX predicate —
// returns the parsed document. Returns ok=false when the attestation isn't
// an SPDX SBOM, so callers can iterate through the attached attestations and
// pick the first SPDX one.
func decodeSPDXFromAttestation(sig spdxSignature) (*spdx.Document, bool, error) {
	payload, err := sig.Payload()
	if err != nil {
		return nil, false, fmt.Errorf("attestation payload: %w", err)
	}
	var env dsseEnvelope
	if err := json.Unmarshal(payload, &env); err != nil {
		// Not all attestations on Chainguard images are DSSE-wrapped JSON;
		// skip anything that fails to parse.
		return nil, false, nil //nolint:nilerr // intentional: skip non-DSSE payloads
	}
	rawStmt, err := base64.StdEncoding.DecodeString(env.Payload)
	if err != nil {
		return nil, false, nil //nolint:nilerr
	}
	var stmt intotoStatement
	if err := json.Unmarshal(rawStmt, &stmt); err != nil {
		return nil, false, nil //nolint:nilerr
	}
	if !strings.HasPrefix(stmt.PredicateType, "https://spdx.dev/") {
		return nil, false, nil
	}
	var doc spdx.Document
	if err := json.Unmarshal(stmt.Predicate, &doc); err != nil {
		return nil, false, fmt.Errorf("parsing SPDX predicate: %w", err)
	}
	return &doc, true, nil
}

// spdxSignature is the subset of cosign's oci.Signature we touch.
type spdxSignature interface {
	Payload() ([]byte, error)
}

type dsseEnvelope struct {
	PayloadType string `json:"payloadType"`
	Payload     string `json:"payload"`
}

type intotoStatement struct {
	Type          string          `json:"_type"`
	PredicateType string          `json:"predicateType"`
	Predicate     json.RawMessage `json:"predicate"`
}
