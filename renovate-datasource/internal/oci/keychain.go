// Package oci fetches OCI image configs and SBOM attestations directly from
// cgr.dev, using a go-containerregistry keychain backed by a caller-supplied
// oauth2.TokenSource that mints cgr.dev-audience tokens.
package oci

import (
	"fmt"
	"strings"

	"github.com/google/go-containerregistry/pkg/authn"
	"golang.org/x/oauth2"
)

const cgrAudience = "cgr.dev"

// Keychain returns an authn.Keychain that authorises requests to cgr.dev (and
// its subdomains) using ts.
//
// ts MUST already yield tokens with the cgr.dev audience — minting them is
// the caller's responsibility because the two auth modes the rest of this
// service supports need different exchange paths:
//
//   - chainctl mode: the chainctl access token can't be re-exchanged via STS
//     (it has the wrong audience as input), so the caller shells out to
//     `chainctl auth token --audience cgr.dev` via auth.NewChainctlTokenSource.
//   - identity mode: the raw workload-identity OIDC token can be exchanged
//     via STS with WithIdentity into the cgr.dev audience.
//
// ts is wrapped with oauth2.ReuseTokenSource so the underlying source is only
// hit when the cached token expires. Non-cgr.dev hosts get anonymous auth so
// the keychain is safe to plug into ggcr without leaking credentials.
func Keychain(ts oauth2.TokenSource) authn.Keychain {
	return cgrKeychain{ts: oauth2.ReuseTokenSource(nil, ts)}
}

type cgrKeychain struct {
	ts oauth2.TokenSource
}

var _ authn.Keychain = (*cgrKeychain)(nil)

func (k cgrKeychain) Resolve(res authn.Resource) (authn.Authenticator, error) {
	r := res.RegistryStr()
	if r != cgrAudience && !strings.HasSuffix(r, "."+cgrAudience) {
		return authn.Anonymous, nil
	}
	tok, err := k.ts.Token()
	if err != nil {
		return nil, fmt.Errorf("getting cgr.dev token: %w", err)
	}
	return &authn.Basic{
		Username: "_token",
		Password: tok.AccessToken,
	}, nil
}
