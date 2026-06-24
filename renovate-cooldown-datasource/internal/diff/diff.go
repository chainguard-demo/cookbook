// Package diff computes a structured diff between two OCI image references
// of the same Chainguard repo. It pulls the image config and the SPDX SBOM
// attestation for each side, then surfaces:
//
//   - apk package changes (added / removed / updated)
//   - upstream source-repo changes (github/gitlab repos the apks vendored)
//   - selected image-config field changes
//
// The package is HTTP-free: the server handler calls Compute and JSON-
// encodes the returned *Response.
package diff

import (
	"context"
	"fmt"
	"time"

	v1 "github.com/google/go-containerregistry/pkg/v1"
	spdx "github.com/spdx/tools-golang/spdx/v2/v2_3"
	"golang.org/x/sync/errgroup"
)

// Response is the JSON shape returned by /v1/diff.
type Response struct {
	From     Ref           `json:"from"`
	To       Ref           `json:"to"`
	Packages Packages      `json:"packages"`
	Sources  Sources       `json:"sources"`
	Config   []ConfigDelta `json:"config"`
}

type Ref struct {
	Timestamp string `json:"timestamp,omitempty"`
	Digest    string `json:"digest"`
	// Platform is "os/arch" from the image config (e.g. "linux/amd64").
	Platform string `json:"platform,omitempty"`
	// MainPackage is the apk package the image is built around, taken from
	// the `dev.chainguard.package.main` config label. Empty if the label
	// isn't set. Surfaced so consumers can highlight the "headline" package
	// among all the transitive ones.
	MainPackage string `json:"mainPackage,omitempty"`
}

type Packages struct {
	Added   []PackageEntry `json:"added"`
	Removed []PackageEntry `json:"removed"`
	Updated []PackageDelta `json:"updated"`
}

type PackageEntry struct {
	Name      string `json:"name"`
	Version   string `json:"version"`
	Ecosystem string `json:"ecosystem,omitempty"`
	Purl      string `json:"purl,omitempty"`
}

type PackageDelta struct {
	Name      string `json:"name"`
	From      string `json:"from"`
	To        string `json:"to"`
	Ecosystem string `json:"ecosystem,omitempty"`
	Purl      string `json:"purl,omitempty"`
}

// Sources surfaces upstream github/gitlab repo movements that the apk
// packages were generated from (via SPDX GENERATED_FROM). Deduped across
// apks: a source shared by multiple apks appears once with a back-reference
// to all of them.
type Sources struct {
	Added   []SourceEntry `json:"added"`
	Removed []SourceEntry `json:"removed"`
	Updated []SourceDelta `json:"updated"`
}

type SourceEntry struct {
	Name     string   `json:"name"`     // repo path, e.g. "kjd/idna"
	Host     string   `json:"host"`     // "github.com" or "gitlab.com"
	Version  string   `json:"version"`  // tag or commit SHA from the purl
	URL      string   `json:"url,omitempty"`
	Packages []string `json:"packages,omitempty"` // apk names that vendor this source
}

type SourceDelta struct {
	Name string `json:"name"`
	Host string `json:"host"`
	From string `json:"from"`
	To   string `json:"to"`
	// URL is the releases-tag page for the "to" version — same shape as
	// SourceEntry.URL so the linked name behaves identically across the
	// added/removed/updated buckets in the UI.
	URL string `json:"url,omitempty"`
	// CompareURL is the from→to compare URL on the upstream host. Renders
	// as a separate "compare" affordance next to the version range.
	CompareURL string   `json:"compareUrl,omitempty"`
	Packages   []string `json:"packages,omitempty"`
}

type ConfigDelta struct {
	Field string `json:"field"`
	From  string `json:"from,omitempty"`
	To    string `json:"to,omitempty"`
	Type  string `json:"type"` // "added" | "removed" | "changed"
}

// Fetcher is the OCI-layer dependency Compute needs. Implementations should
// resolve refs to per-platform manifest digests and fetch the corresponding
// image config and SPDX SBOM attestation. *oci.Fetcher in this codebase
// satisfies it structurally.
type Fetcher interface {
	ResolveDigest(ctx context.Context, repo, ref string) (string, error)
	Config(ctx context.Context, repo, ref string) (*v1.ConfigFile, error)
	SBOMSPDX(ctx context.Context, repo, ref string) (*spdx.Document, error)
}

// mainPackageLabel is the OCI config label Chainguard sets to identify the
// apk package an image is built around. Read by Compute and surfaced as
// Ref.MainPackage.
const mainPackageLabel = "dev.chainguard.package.main"

// Compute drives the OCI calls and builds the response.
//
// The from-side and to-side fetches run concurrently via errgroup. Within
// each side we ResolveDigest first so Config and SBOMSPDX share the resolved
// per-platform digest and don't each re-do the platform negotiation; the two
// subsequent calls run sequentially for simplicity. We fetch the full SBOM
// (packages + relationships) on each side because the per-source changelog
// URLs are derived from SPDX GENERATED_FROM links between each apk and its
// upstream github/gitlab source.
func Compute(ctx context.Context, f Fetcher, repo, fromRef, toRef string) (*Response, error) {
	var (
		fromCfg, toCfg       *v1.ConfigFile
		fromDigest, toDigest string
		fromSBOM, toSBOM     *sbom
	)

	fetchSide := func(ctx context.Context, ref string, cfgOut **v1.ConfigFile, digestOut *string, sbomOut **sbom, label string) error {
		digest, err := f.ResolveDigest(ctx, repo, ref)
		if err != nil {
			return fmt.Errorf("%s resolve: %w", label, err)
		}
		cfg, err := f.Config(ctx, repo, digest)
		if err != nil {
			return fmt.Errorf("%s config: %w", label, err)
		}
		doc, err := f.SBOMSPDX(ctx, repo, digest)
		if err != nil {
			return fmt.Errorf("%s sbom: %w", label, err)
		}
		*cfgOut, *digestOut, *sbomOut = cfg, digest, sbomFromSPDX(doc)
		return nil
	}

	eg, egCtx := errgroup.WithContext(ctx)
	eg.Go(func() error { return fetchSide(egCtx, fromRef, &fromCfg, &fromDigest, &fromSBOM, "from") })
	eg.Go(func() error { return fetchSide(egCtx, toRef, &toCfg, &toDigest, &toSBOM, "to") })
	if err := eg.Wait(); err != nil {
		return nil, err
	}

	return &Response{
		From: Ref{
			Digest:      fromDigest,
			Timestamp:   formatTimestamp(fromCfg.Created.Time),
			Platform:    platformOf(fromCfg),
			MainPackage: fromCfg.Config.Labels[mainPackageLabel],
		},
		To: Ref{
			Digest:      toDigest,
			Timestamp:   formatTimestamp(toCfg.Created.Time),
			Platform:    platformOf(toCfg),
			MainPackage: toCfg.Config.Labels[mainPackageLabel],
		},
		Packages: diffAPKPackages(collectAPKEntries(fromSBOM), collectAPKEntries(toSBOM)),
		Sources:  diffSources(collectSources(fromSBOM), collectSources(toSBOM)),
		Config:   diffConfig(fromCfg, toCfg),
	}, nil
}

// platformOf renders a ConfigFile's OS+Architecture as "os/arch", falling
// back to just one side if the other is missing.
func platformOf(c *v1.ConfigFile) string {
	if c == nil {
		return ""
	}
	switch {
	case c.OS != "" && c.Architecture != "":
		return c.OS + "/" + c.Architecture
	case c.OS != "":
		return c.OS
	case c.Architecture != "":
		return c.Architecture
	}
	return ""
}

// formatTimestamp emits RFC3339 with millisecond precision. Returns "" for
// the zero time so the JSON field is omitted.
func formatTimestamp(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format("2006-01-02T15:04:05.000Z")
}
