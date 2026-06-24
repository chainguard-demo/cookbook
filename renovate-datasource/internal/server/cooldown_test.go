package server

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"

	"github.com/chainguard-demo/cookbook/renovate-datasource/internal/chainguard"
)

func TestApplyCooldown(t *testing.T) {
	now := time.Date(2026, 6, 22, 12, 0, 0, 0, time.UTC)
	cooldown := 7 * 24 * time.Hour
	cutoff := now.Add(-cooldown)

	day := func(d int) time.Time { return now.AddDate(0, 0, -d) }

	tests := []struct {
		name    string
		tags    []chainguard.Tag
		history map[string][]chainguard.TagHistory
		histErr error
		want    []Release
		wantErr bool
	}{
		{
			name: "current digest older than cutoff passes through",
			tags: []chainguard.Tag{
				{ID: "1.21", Name: "1.21", LastUpdated: day(30), Digest: "sha256:old"},
			},
			want: []Release{
				{Version: "1.21", ReleaseTimestamp: day(30), Digest: "sha256:old"},
			},
		},
		{
			name: "current digest exactly at cutoff is treated as old enough",
			tags: []chainguard.Tag{
				{ID: "latest", Name: "latest", LastUpdated: cutoff, Digest: "sha256:edge"},
			},
			want: []Release{
				{Version: "latest", ReleaseTimestamp: cutoff, Digest: "sha256:edge"},
			},
		},
		{
			name: "current digest too new, picks newest history entry <= cutoff",
			tags: []chainguard.Tag{
				{ID: "latest", Name: "latest", LastUpdated: day(2), Digest: "sha256:new"},
			},
			history: map[string][]chainguard.TagHistory{
				"latest": {
					{UpdateTimestamp: day(20), Digest: "sha256:older"},
					{UpdateTimestamp: day(10), Digest: "sha256:rewind"},
					{UpdateTimestamp: day(2), Digest: "sha256:new"},
				},
			},
			want: []Release{
				{Version: "latest", ReleaseTimestamp: day(10), Digest: "sha256:rewind"},
			},
		},
		{
			name: "current digest too new and no history entry old enough is omitted",
			tags: []chainguard.Tag{
				{ID: "latest-dev", Name: "latest-dev", LastUpdated: day(1), Digest: "sha256:fresh"},
			},
			history: map[string][]chainguard.TagHistory{
				"latest-dev": {
					{UpdateTimestamp: day(3), Digest: "sha256:still-too-new"},
					{UpdateTimestamp: day(1), Digest: "sha256:fresh"},
				},
			},
			want: []Release{},
		},
		{
			name: "current digest too new, history is empty, omitted",
			tags: []chainguard.Tag{
				{ID: "brand-new", Name: "brand-new", LastUpdated: day(0), Digest: "sha256:just-now"},
			},
			history: map[string][]chainguard.TagHistory{
				"brand-new": {},
			},
			want: []Release{},
		},
		{
			name: "mixed: one passes through, one rewinds, one drops",
			tags: []chainguard.Tag{
				{ID: "stable", Name: "stable", LastUpdated: day(15), Digest: "sha256:stable"},
				{ID: "latest", Name: "latest", LastUpdated: day(1), Digest: "sha256:latest-now"},
				{ID: "new-tag", Name: "new-tag", LastUpdated: day(0), Digest: "sha256:nothing-old"},
			},
			history: map[string][]chainguard.TagHistory{
				"latest": {
					{UpdateTimestamp: day(14), Digest: "sha256:latest-cooled"},
					{UpdateTimestamp: day(1), Digest: "sha256:latest-now"},
				},
				"new-tag": {
					{UpdateTimestamp: day(0), Digest: "sha256:nothing-old"},
				},
			},
			want: []Release{
				{Version: "stable", ReleaseTimestamp: day(15), Digest: "sha256:stable"},
				{Version: "latest", ReleaseTimestamp: day(14), Digest: "sha256:latest-cooled"},
			},
		},
		{
			name: "history lookup error is propagated",
			tags: []chainguard.Tag{
				{ID: "latest", Name: "latest", LastUpdated: day(1), Digest: "sha256:new"},
			},
			histErr: errors.New("boom"),
			wantErr: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			histFn := func(_ context.Context, tagID string) ([]chainguard.TagHistory, error) {
				if tc.histErr != nil {
					return nil, tc.histErr
				}
				return tc.history[tagID], nil
			}

			got, err := applyCooldown(context.Background(), tc.tags, cutoff, histFn, 1)
			if (err != nil) != tc.wantErr {
				t.Fatalf("applyCooldown error = %v, wantErr=%v", err, tc.wantErr)
			}
			if tc.wantErr {
				return
			}
			if len(got) != len(tc.want) {
				t.Fatalf("len(got)=%d want %d (got=%+v)", len(got), len(tc.want), got)
			}
			for i := range got {
				if got[i] != tc.want[i] {
					t.Errorf("release[%d] = %+v, want %+v", i, got[i], tc.want[i])
				}
			}
		})
	}
}

// TestApplyCooldown_FansOutHistoryCalls verifies that history lookups happen
// in parallel up to the configured concurrency.
func TestApplyCooldown_FansOutHistoryCalls(t *testing.T) {
	const (
		numTags     = 50
		concurrency = 10
		histDelay   = 50 * time.Millisecond
	)

	now := time.Now()
	cutoff := now.Add(-7 * 24 * time.Hour)

	tags := make([]chainguard.Tag, numTags)
	for i := range tags {
		name := "tag-" + string(rune('A'+i))
		tags[i] = chainguard.Tag{
			ID:          name,
			Name:        name,
			LastUpdated: now,
			Digest:      "sha256:current",
		}
	}

	var (
		inFlight atomic.Int32
		peak     atomic.Int32
	)
	recordPeak := func(v int32) {
		for {
			old := peak.Load()
			if v <= old || peak.CompareAndSwap(old, v) {
				return
			}
		}
	}

	histFn := func(ctx context.Context, _ string) ([]chainguard.TagHistory, error) {
		recordPeak(inFlight.Add(1))
		defer inFlight.Add(-1)
		select {
		case <-time.After(histDelay):
		case <-ctx.Done():
			return nil, ctx.Err()
		}
		return []chainguard.TagHistory{
			{UpdateTimestamp: cutoff.Add(-time.Hour), Digest: "sha256:cooled"},
		}, nil
	}

	start := time.Now()
	releases, err := applyCooldown(context.Background(), tags, cutoff, histFn, concurrency)
	elapsed := time.Since(start)

	if err != nil {
		t.Fatalf("applyCooldown: %v", err)
	}
	if len(releases) != numTags {
		t.Fatalf("got %d releases, want %d", len(releases), numTags)
	}

	if elapsed > histDelay*time.Duration(numTags/2) {
		t.Errorf("applyCooldown took %v; fan-out doesn't appear to be working", elapsed)
	}
	if peak.Load() < int32(concurrency)-1 {
		t.Errorf("peak in-flight history calls = %d, want close to %d", peak.Load(), concurrency)
	}
}
