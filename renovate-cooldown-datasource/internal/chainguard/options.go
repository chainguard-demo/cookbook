package chainguard

type options struct {
	mode          authMode
	identity      string
	identityToken string
}

// Option configures New.
type Option func(*options)

// WithIdentity selects assumable-identity auth: the workload-identity token
// is STS-exchanged for a Chainguard token using the given identity UIDP.
//
// token may be either a literal JWT or a filesystem path to a file holding
// one. File-based tokens are re-read on demand so Kubernetes service-account
// token rotation works without restarts.
//
// If WithIdentity is omitted, New falls back to the local chainctl token
// cache (run `chainctl auth login` beforehand).
func WithIdentity(identityUIDP, token string) Option {
	return func(o *options) {
		o.mode = authIdentity
		o.identity = identityUIDP
		o.identityToken = token
	}
}
