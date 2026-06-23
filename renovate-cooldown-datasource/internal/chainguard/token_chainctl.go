package chainguard

import (
	"fmt"
	"time"

	"chainguard.dev/sdk/auth"
	"chainguard.dev/sdk/auth/token"
	"golang.org/x/oauth2"
)

// loadChainctlToken validates that there's a non-expired access token in the
// chainctl cache and returns its bytes. Used both for the startup sanity
// check and as the inner read in chainctlTokenSource.
func loadChainctlToken() (string, error) {
	if life := token.RemainingLife(token.KindAccess, audience, time.Minute); life <= 0 {
		return "", fmt.Errorf("no usable chainctl token for audience %q; run `chainctl auth login`", audience)
	}
	b, err := token.Load(token.KindAccess, audience)
	if err != nil {
		return "", fmt.Errorf("loading chainctl token: %w", err)
	}
	return string(b), nil
}

// chainctlTokenSource serves the access token from the chainctl cache,
// re-reading from disk on each call. Wrapped with oauth2.ReuseTokenSource so
// the disk is hit only when the cached token's expiry passes.
type chainctlTokenSource struct{}

func (chainctlTokenSource) Token() (*oauth2.Token, error) {
	s, err := loadChainctlToken()
	if err != nil {
		return nil, err
	}
	exp, err := auth.ExtractExpiry(s)
	if err != nil {
		// If we can't parse the expiry, force a re-read every minute.
		exp = time.Now().Add(time.Minute)
	}
	return &oauth2.Token{AccessToken: s, Expiry: exp}, nil
}
