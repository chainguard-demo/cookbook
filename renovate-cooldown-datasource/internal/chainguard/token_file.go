package chainguard

import (
	"fmt"
	"os"
	"strings"
	"time"

	"golang.org/x/oauth2"
)

// buildBaseTokenSource returns an oauth2.TokenSource for the raw workload OIDC
// token (pre-STS-exchange), plus the file path if the input pointed at a file
// (used to power Ready()).
func buildBaseTokenSource(value string) (oauth2.TokenSource, string, error) {
	if fi, err := os.Stat(value); err == nil && fi.Mode().IsRegular() {
		if _, err := os.ReadFile(value); err != nil {
			return nil, "", fmt.Errorf("reading identity token file %s: %w", value, err)
		}
		return &fileTokenSource{path: value}, value, nil
	}
	return &staticTokenSource{token: strings.TrimSpace(value)}, "", nil
}

// fileTokenSource re-reads the OIDC token from disk on demand so it picks up
// Kubernetes service-account token rotation. A short Expiry forces frequent
// reloads; the wrapping STS source caches the exchanged Chainguard token.
type fileTokenSource struct{ path string }

func (f *fileTokenSource) Token() (*oauth2.Token, error) {
	b, err := os.ReadFile(f.path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", f.path, err)
	}
	return &oauth2.Token{
		AccessToken: strings.TrimSpace(string(b)),
		Expiry:      time.Now().Add(time.Minute),
	}, nil
}
