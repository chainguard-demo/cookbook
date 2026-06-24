package chainguard

import (
	"time"

	"chainguard.dev/sdk/auth"
	"golang.org/x/oauth2"
)

// staticTokenSource serves a literal token. Expiry is derived from the JWT's
// `exp` claim if parseable, otherwise set far in the future.
type staticTokenSource struct{ token string }

func (s *staticTokenSource) Token() (*oauth2.Token, error) {
	exp, err := auth.ExtractExpiry(s.token)
	if err != nil {
		exp = time.Now().Add(24 * time.Hour)
	}
	return &oauth2.Token{AccessToken: s.token, Expiry: exp}, nil
}
