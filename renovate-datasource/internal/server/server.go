package server

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/google/go-containerregistry/pkg/v1/remote/transport"

	"github.com/chainguard-demo/cookbook/renovate-datasource/internal/chainguard"
	"github.com/chainguard-demo/cookbook/renovate-datasource/internal/diff"
	"github.com/chainguard-demo/cookbook/renovate-datasource/internal/oci"
)

// Conservative repo-name pattern: lowercase, digits, dashes, underscores,
// dots, and single internal slashes. Blocks `..`, leading dots, query strings.
var repoNamePattern = regexp.MustCompile(`^[a-z0-9]([a-z0-9._-]*[a-z0-9])?(/[a-z0-9]([a-z0-9._-]*[a-z0-9])?)*$`)

// tagPattern matches the OCI distribution tag spec: 1–128 chars from
// [A-Za-z0-9_.-], starting with [A-Za-z0-9_] (no leading dot or dash).
var tagPattern = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$`)

// digestPattern matches the only OCI digest form we accept: sha256 + 64 hex.
var digestPattern = regexp.MustCompile(`^sha256:[a-f0-9]{64}$`)

// validRef reports whether ref is a well-formed OCI tag or a sha256 digest.
// Validating at the server boundary lets us 400 fast on bad input rather
// than passing it to the registry and reporting a generic 502.
func validRef(ref string) bool {
	if strings.HasPrefix(ref, "sha256:") {
		return digestPattern.MatchString(ref)
	}
	return tagPattern.MatchString(ref)
}

// Backend is the subset of *chainguard.Client the HTTP layer depends on for
// platform-API calls (listing tags + history, readiness).
type Backend interface {
	ListTags(ctx context.Context, repo string) ([]chainguard.Tag, error)
	ListTagHistory(ctx context.Context, tagID string) ([]chainguard.TagHistory, error)
	Ready(ctx context.Context) error
}

const (
	defaultCooldown           = 7 * 24 * time.Hour
	defaultHistoryConcurrency = 16
)

type options struct {
	cooldown           time.Duration
	historyConcurrency int
	orgName            string
	log                *slog.Logger
	now                func() time.Time
}

// Option configures New.
type Option func(*options)

// WithCooldown sets the cooldown window. Default is 168h (7 days). A value of
// 0 disables the cooldown — the /v1/releases/{repo} endpoint then serves the
// upstream tag list as-is, skipping the per-tag history rewind.
func WithCooldown(d time.Duration) Option {
	return func(o *options) { o.cooldown = d }
}

// WithHistoryConcurrency caps the parallel ListTagHistory calls per request.
// Default is 16.
func WithHistoryConcurrency(n int) Option {
	return func(o *options) { o.historyConcurrency = n }
}

// WithLogger sets the structured logger. Default is slog.Default().
func WithLogger(l *slog.Logger) Option {
	return func(o *options) { o.log = l }
}

// WithOrgName sets the Chainguard org name used to build the "view in
// console" link on the diff page. When empty, the link is omitted.
func WithOrgName(name string) Option {
	return func(o *options) { o.orgName = name }
}

type Server struct {
	backend            Backend
	fetcher            diff.Fetcher
	cooldown           time.Duration
	historyConcurrency int
	orgName            string
	now                func() time.Time
	log                *slog.Logger
}

// New builds a Server. backend handles platform-API calls (releases endpoint);
// fetcher handles direct cgr.dev access (diff endpoint). Both are required;
// everything else has a default.
func New(backend Backend, fetcher diff.Fetcher, opts ...Option) *Server {
	o := options{
		cooldown:           defaultCooldown,
		historyConcurrency: defaultHistoryConcurrency,
		log:                slog.Default(),
		now:                time.Now,
	}
	for _, fn := range opts {
		fn(&o)
	}
	return &Server{
		backend:            backend,
		fetcher:            fetcher,
		cooldown:           o.cooldown,
		historyConcurrency: o.historyConcurrency,
		orgName:            o.orgName,
		now:                o.now,
		log:                o.log,
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		if err := s.backend.Ready(r.Context()); err != nil {
			// Log the detail server-side; respond with a generic message so
			// unauthenticated probes can't enumerate internal filesystem
			// paths or audiences via the readiness endpoint.
			s.log.WarnContext(r.Context(), "not ready", "err", err)
			writeAPIError(w, http.StatusServiceUnavailable, "The service isn't ready yet.")
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("GET /v1/releases/{repo...}", s.handleReleases)
	mux.HandleFunc("GET /v1/diff/{repo}/{from}/{to}", s.handleDiff)
	mux.HandleFunc("GET /repo/{repo}/diff/{oldRef}/{newRef}", s.handleDiffPage)
	return mux
}

func (s *Server) handleDiff(w http.ResponseWriter, r *http.Request) {
	repo := r.PathValue("repo")
	from := r.PathValue("from")
	to := r.PathValue("to")
	s.log.InfoContext(r.Context(), "diff request", "repo", repo, "from", from, "to", to, "remote", r.RemoteAddr, "ua", r.UserAgent())

	if !repoNamePattern.MatchString(repo) {
		writeAPIError(w, http.StatusBadRequest, "The repo name isn't a valid OCI repository path.")
		return
	}
	if !validRef(from) {
		writeAPIError(w, http.StatusBadRequest, "The 'from' ref isn't a valid OCI tag or sha256 digest.")
		return
	}
	if !validRef(to) {
		writeAPIError(w, http.StatusBadRequest, "The 'to' ref isn't a valid OCI tag or sha256 digest.")
		return
	}

	ctx := r.Context()
	resp, err := diff.Compute(ctx, s.fetcher, repo, from, to)
	if err != nil {
		status, msg := classifyDiffError(err)
		// 5xx errors deserve an ERROR log line — the server is the source
		// of the problem (or its upstream). 4xx are client problems; we
		// log them at Info so they don't pollute the error stream.
		if status >= 500 {
			s.log.ErrorContext(ctx, "diff.Compute failed", "repo", repo, "from", from, "to", to, "err", err)
		} else {
			s.log.InfoContext(ctx, "diff.Compute client error", "repo", repo, "from", from, "to", to, "status", status, "err", err)
		}
		writeAPIError(w, status, msg)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		s.log.ErrorContext(ctx, "encoding diff response", "repo", repo, "err", err)
	}
}

// classifyDiffError maps an error from diff.Compute into the HTTP status and
// client-facing message we want to return. The two interesting cases are:
//
//   - the registry told us the image/tag doesn't exist (transport.Error 404)
//     → 404 with a clear message, not the generic upstream-error 502;
//   - the image exists but has no SBOM attestation (oci.ErrNoSBOM) → 422,
//     since the request is well-formed but undiffable.
//
// Everything else falls through to 502.
func classifyDiffError(err error) (int, string) {
	var te *transport.Error
	if errors.As(err, &te) {
		switch te.StatusCode {
		case http.StatusNotFound:
			return http.StatusNotFound, "This tag or digest doesn't exist in the registry."
		case http.StatusUnauthorized, http.StatusForbidden:
			return http.StatusBadGateway, "Failed to authenticate with the upstream registry."
		}
	}
	if errors.Is(err, oci.ErrNoSBOM) {
		return http.StatusUnprocessableEntity, "This image has no SBOM attestation, so a diff can't be computed."
	}
	return http.StatusBadGateway, "The upstream registry returned an error. Please try again in a moment."
}

func (s *Server) handleReleases(w http.ResponseWriter, r *http.Request) {
	repo := r.PathValue("repo")
	s.log.InfoContext(r.Context(), "request", "repo", repo, "remote", r.RemoteAddr, "ua", r.UserAgent())
	if !repoNamePattern.MatchString(repo) {
		writeAPIError(w, http.StatusBadRequest, "The repo name isn't a valid OCI repository path.")
		return
	}

	ctx := r.Context()
	tags, err := s.backend.ListTags(ctx, repo)
	if err != nil {
		if errors.Is(err, chainguard.ErrRepoNotFound) {
			writeAPIError(w, http.StatusNotFound, "No repository with that name in this org.")
			return
		}
		s.log.ErrorContext(ctx, "ListTags failed", "repo", repo, "err", err)
		writeAPIError(w, http.StatusBadGateway, "The upstream registry returned an error. Please try again in a moment.")
		return
	}

	var releases []Release
	if s.cooldown <= 0 {
		// Cooldown disabled — emit each tag's current state straight through,
		// no history walk. Matches the behaviour Renovate would see if it
		// hit cgr.dev directly, but keeps the changelog/diff plumbing the
		// rest of the service provides.
		releases = tagsAsReleases(tags)
	} else {
		cutoff := s.now().Add(-s.cooldown)
		releases, err = applyCooldown(ctx, tags, cutoff, s.backend.ListTagHistory, s.historyConcurrency)
		if err != nil {
			s.log.ErrorContext(ctx, "applyCooldown failed", "repo", repo, "err", err)
			writeAPIError(w, http.StatusBadGateway, "The upstream registry returned an error. Please try again in a moment.")
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(Response{Releases: releases}); err != nil {
		s.log.ErrorContext(ctx, "encoding response", "repo", repo, "err", err)
	}
}
