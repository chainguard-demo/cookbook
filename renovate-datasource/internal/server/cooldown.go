package server

import (
	"context"
	"fmt"
	"time"

	"golang.org/x/sync/errgroup"

	"github.com/chainguard-demo/cookbook/renovate-datasource/internal/chainguard"
)

// DefaultHistoryConcurrency is the default fan-out used when applyCooldown is
// given concurrency <= 0.
const DefaultHistoryConcurrency = 16

// Release is one entry in the Renovate custom-datasource response.
type Release struct {
	Version          string    `json:"version"`
	ReleaseTimestamp time.Time `json:"releaseTimestamp"`
	Digest           string    `json:"digest"`
}

// Response is the top-level shape returned by /v1/releases/{repo}.
type Response struct {
	Releases []Release `json:"releases"`
}

// tagsAsReleases emits each tag's current state as a Release, without any
// cooldown rewind. Used by the releases handler when the cooldown is set to
// 0 (disabled), so the datasource behaves as a thin pass-through of the
// upstream tag list.
func tagsAsReleases(tags []chainguard.Tag) []Release {
	out := make([]Release, 0, len(tags))
	for _, t := range tags {
		out = append(out, Release{
			Version:          t.Name,
			ReleaseTimestamp: t.LastUpdated,
			Digest:           t.Digest,
		})
	}
	return out
}

// historyFn returns the historical iterations of the tag identified by tagID.
type historyFn func(ctx context.Context, tagID string) ([]chainguard.TagHistory, error)

// applyCooldown produces the Renovate releases view for a set of tags.
//
// For each tag:
//   - if the tag's current digest is on or before the cutoff, emit it as-is;
//   - if it's after the cutoff, walk history and emit the most recent entry
//     whose UpdateTimestamp is on or before the cutoff;
//   - if no such history entry exists, omit the tag.
//
// History lookups are dispatched concurrently with a bound of `concurrency`
// (DefaultHistoryConcurrency if <= 0). Output order matches input order.
func applyCooldown(ctx context.Context, tags []chainguard.Tag, cutoff time.Time, history historyFn, concurrency int) ([]Release, error) {
	if concurrency <= 0 {
		concurrency = DefaultHistoryConcurrency
	}

	// Pre-allocate output slots so we can preserve input order regardless of
	// the order in which the concurrent history calls complete. A nil slot
	// means "omit from response".
	slots := make([]*Release, len(tags))
	var needHistory []int

	for i, t := range tags {
		if !t.LastUpdated.After(cutoff) {
			slots[i] = &Release{
				Version:          t.Name,
				ReleaseTimestamp: t.LastUpdated,
				Digest:           t.Digest,
			}
			continue
		}
		needHistory = append(needHistory, i)
	}

	if len(needHistory) > 0 {
		eg, egCtx := errgroup.WithContext(ctx)
		eg.SetLimit(concurrency)

		for _, idx := range needHistory {
			t := tags[idx]
			eg.Go(func() error {
				hist, err := history(egCtx, t.ID)
				if err != nil {
					return fmt.Errorf("history(%s): %w", t.Name, err)
				}
				var best *chainguard.TagHistory
				for j := range hist {
					e := &hist[j]
					if e.UpdateTimestamp.After(cutoff) {
						continue
					}
					if best == nil || e.UpdateTimestamp.After(best.UpdateTimestamp) {
						best = e
					}
				}
				if best == nil {
					return nil
				}
				slots[idx] = &Release{
					Version:          t.Name,
					ReleaseTimestamp: best.UpdateTimestamp,
					Digest:           best.Digest,
				}
				return nil
			})
		}
		if err := eg.Wait(); err != nil {
			return nil, err
		}
	}

	out := make([]Release, 0, len(tags))
	for _, r := range slots {
		if r != nil {
			out = append(out, *r)
		}
	}
	return out, nil
}
