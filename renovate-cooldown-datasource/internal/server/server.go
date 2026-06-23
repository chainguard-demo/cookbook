package server

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"time"

	"github.com/chainguard-demo/cookbook/renovate-cooldown-datasource/internal/chainguard"
)

// Conservative repo-name pattern: lowercase, digits, dashes, underscores,
// dots, and single internal slashes. Blocks `..`, leading dots, query strings.
var repoNamePattern = regexp.MustCompile(`^[a-z0-9]([a-z0-9._-]*[a-z0-9])?(/[a-z0-9]([a-z0-9._-]*[a-z0-9])?)*$`)

// Backend is the subset of *chainguard.Client the HTTP layer depends on,
// kept narrow so tests can substitute a fake.
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
	log                *slog.Logger
	now                func() time.Time
}

// Option configures New.
type Option func(*options)

// WithCooldown sets the cooldown window. Default is 168h (7 days).
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

type Server struct {
	backend            Backend
	cooldown           time.Duration
	historyConcurrency int
	now                func() time.Time
	log                *slog.Logger
}

// New builds a Server. backend is required; everything else has a default.
func New(backend Backend, opts ...Option) *Server {
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
		cooldown:           o.cooldown,
		historyConcurrency: o.historyConcurrency,
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
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("GET /v1/{repo...}", s.handleRepo)
	return mux
}

func (s *Server) handleRepo(w http.ResponseWriter, r *http.Request) {
	repo := r.PathValue("repo")
	s.log.InfoContext(r.Context(), "request", "repo", repo, "remote", r.RemoteAddr, "ua", r.UserAgent())
	if !repoNamePattern.MatchString(repo) {
		http.Error(w, "invalid repo name", http.StatusBadRequest)
		return
	}

	ctx := r.Context()
	tags, err := s.backend.ListTags(ctx, repo)
	if err != nil {
		if errors.Is(err, chainguard.ErrRepoNotFound) {
			http.Error(w, "repo not found", http.StatusNotFound)
			return
		}
		s.log.ErrorContext(ctx, "ListTags failed", "repo", repo, "err", err)
		http.Error(w, "upstream error", http.StatusBadGateway)
		return
	}

	cutoff := s.now().Add(-s.cooldown)
	releases, err := applyCooldown(ctx, tags, cutoff, s.backend.ListTagHistory, s.historyConcurrency)
	if err != nil {
		s.log.ErrorContext(ctx, "applyCooldown failed", "repo", repo, "err", err)
		http.Error(w, "upstream error", http.StatusBadGateway)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(Response{Releases: releases}); err != nil {
		s.log.ErrorContext(ctx, "encoding response", "repo", repo, "err", err)
	}
}
