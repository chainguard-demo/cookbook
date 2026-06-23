package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/spf13/cobra"

	"github.com/chainguard-demo/cookbook/renovate-cooldown-datasource/internal/chainguard"
	"github.com/chainguard-demo/cookbook/renovate-cooldown-datasource/internal/server"
)

type options struct {
	port               int
	cooldown           time.Duration
	org                string
	apiURL             string
	historyConcurrency int

	identity      string
	identityToken string
}

func main() {
	if err := newRootCmd().Execute(); err != nil {
		os.Exit(1)
	}
}

func newRootCmd() *cobra.Command {
	opts := &options{}
	cmd := &cobra.Command{
		Use:   "renovate-cooldown-datasource",
		Short: "Renovate custom datasource that serves cooled-down Chainguard image tags",
		Long: `An HTTP service that acts as a Renovate custom datasource for a single
Chainguard org. Tags whose current digest has been stable for at least the
configured cooldown are served as-is; tags newer than the cooldown are
rewound to the most recent historical digest that satisfies the cooldown,
and tags with no such history entry are omitted entirely.

Authentication:
  By default the service loads the chainctl token from disk
  (run "chainctl auth login" beforehand).

  For deployed environments, pass --identity (an assumable identity UIDP)
  together with --identity-token (either a path to an OIDC token file or
  a literal token string). When the value points at a file, the file is
  re-read on demand so Kubernetes service-account token rotation works.`,
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return run(cmd.Context(), opts)
		},
	}

	cmd.Flags().IntVar(&opts.port, "port", 8080, "HTTP listen port")
	cmd.Flags().DurationVar(&opts.cooldown, "cooldown", 7*24*time.Hour, "cooldown window (Go duration, e.g. 168h, 72h, 24h)")
	cmd.Flags().StringVar(&opts.org, "org", "", "Chainguard org/group name (required)")
	cmd.Flags().StringVar(&opts.apiURL, "api-url", "https://console-api.enforce.dev", "Chainguard platform API URL")
	cmd.Flags().IntVar(&opts.historyConcurrency, "history-concurrency", 16, "max concurrent ListTagHistory calls per request")
	cmd.Flags().StringVar(&opts.identity, "identity", "", "UIDP of an assumable Chainguard identity (enables identity auth)")
	cmd.Flags().StringVar(&opts.identityToken, "identity-token", "", "OIDC token to assume the identity; either a file path or a literal JWT")
	_ = cmd.MarkFlagRequired("org")

	return cmd
}

func run(parent context.Context, opts *options) error {
	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))

	cgOpts, authLbl, err := chainguardOptions(opts)
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(parent, os.Interrupt, syscall.SIGTERM)
	defer stop()

	cg, err := chainguard.New(ctx, opts.org, cgOpts...)
	if err != nil {
		log.Error("initializing Chainguard client", "err", err)
		return fmt.Errorf("initializing Chainguard client: %w", err)
	}
	defer cg.Close()

	log.Info("resolved org", "org", opts.org, "uidp", cg.OrgUIDP, "cooldown", opts.cooldown, "auth", authLbl)

	srv := &http.Server{
		Addr: net.JoinHostPort("", strconv.Itoa(opts.port)),
		Handler: server.New(cg,
			server.WithCooldown(opts.cooldown),
			server.WithHistoryConcurrency(opts.historyConcurrency),
			server.WithLogger(log),
		).Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
		close(errCh)
	}()

	select {
	case err := <-errCh:
		log.Error("server stopped unexpectedly", "err", err)
		return err
	case <-ctx.Done():
		log.Info("shutdown signal received")
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Error("graceful shutdown failed", "err", err)
		return err
	}
	return nil
}

// chainguardOptions translates CLI flags into chainguard.Option values, plus
// a label for the startup log line.
func chainguardOptions(opts *options) ([]chainguard.Option, string, error) {
	out := []chainguard.Option{chainguard.WithAPIURL(opts.apiURL)}
	switch {
	case opts.identity != "" && opts.identityToken != "":
		out = append(out, chainguard.WithIdentity(opts.identity, opts.identityToken))
		return out, "identity", nil
	case opts.identity != "" || opts.identityToken != "":
		return nil, "", errors.New("--identity and --identity-token must be set together")
	default:
		return out, "chainctl", nil
	}
}
