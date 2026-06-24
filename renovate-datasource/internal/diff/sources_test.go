package diff

import (
	"reflect"
	"sort"
	"testing"
)

// gen builds a GENERATED_FROM relationship in the shape SPDX uses.
func gen(from, to string) sbomRelationship {
	return sbomRelationship{From: from, Type: "GENERATED_FROM", To: to}
}

func srcPkg(id, host, path, version string) sbomPackage {
	return sbomPackage{
		ID:      id,
		Name:    path,
		Version: version,
		Purl:    "pkg:" + hostToScheme(host) + "/" + path + "@" + version,
	}
}

func hostToScheme(host string) string {
	switch host {
	case "github.com":
		return "github"
	case "gitlab.com":
		return "gitlab"
	}
	return host
}

func TestCollectSources_DedupsAcrossApks(t *testing.T) {
	// python-3.14 and python-3.14-base both GENERATED_FROM cpython@v3.14.5.
	// Expected: one cpython entry, with both apk names in agg.apks.
	s := &sbom{
		Packages: []sbomPackage{
			apkPkg("apk-python", "python-3.14", "3.14.5-r0"),
			apkPkg("apk-python-base", "python-3.14-base", "3.14.5-r0"),
			srcPkg("src-cpython", "github.com", "python/cpython", "v3.14.5"),
		},
		Relationships: []sbomRelationship{
			gen("apk-python", "src-cpython"),
			gen("apk-python-base", "src-cpython"),
		},
	}
	got := collectSources(s)
	if len(got) != 1 {
		t.Fatalf("got %d aggregates, want 1: %+v", len(got), got)
	}
	agg := got["github.com|python/cpython"]
	if agg.ref.version != "v3.14.5" {
		t.Errorf("version = %q, want v3.14.5", agg.ref.version)
	}
	sort.Strings(agg.apks)
	wantApks := []string{"python-3.14", "python-3.14-base"}
	if !reflect.DeepEqual(agg.apks, wantApks) {
		t.Errorf("apks = %v, want %v", agg.apks, wantApks)
	}
}

func TestCollectSources_IgnoresNonAPKAndNonSource(t *testing.T) {
	// An apk → non-source-purl relationship, and a source package nobody
	// references — both should produce zero aggregates.
	s := &sbom{
		Packages: []sbomPackage{
			apkPkg("apk-1", "x", "1.0"),
			{ID: "other-1", Name: "other", Version: "1.0", Purl: "pkg:rpm/fedora/other@1.0"},
			srcPkg("orphan-src", "github.com", "owner/repo", "v1.0"),
		},
		Relationships: []sbomRelationship{
			gen("apk-1", "other-1"), // apk → non-source
			// no relationship pointing at orphan-src
		},
	}
	got := collectSources(s)
	if len(got) != 0 {
		t.Errorf("expected 0 aggregates, got %d: %+v", len(got), got)
	}
}

func TestCollectSources_NonGeneratedFromIgnored(t *testing.T) {
	// Only GENERATED_FROM relationships should drive source collection.
	s := &sbom{
		Packages: []sbomPackage{
			apkPkg("apk-1", "x", "1.0"),
			srcPkg("src-1", "github.com", "owner/repo", "v1.0"),
		},
		Relationships: []sbomRelationship{
			{From: "apk-1", Type: "DEPENDS_ON", To: "src-1"},
		},
	}
	got := collectSources(s)
	if len(got) != 0 {
		t.Errorf("DEPENDS_ON should be ignored, got %+v", got)
	}
}

func TestDiffSources(t *testing.T) {
	from := map[string]sourceAggregate{
		"github.com|libffi/libffi": {
			ref:  sourceRef{host: "github.com", path: "libffi/libffi", version: "v3.5.2"},
			apks: []string{"libffi"},
		},
		"github.com|kjd/idna": { // unchanged version — should NOT appear
			ref:  sourceRef{host: "github.com", path: "kjd/idna", version: "v3.10"},
			apks: []string{"py3-idna"},
		},
		"github.com|gone/repo": { // removed
			ref:  sourceRef{host: "github.com", path: "gone/repo", version: "v1.0"},
			apks: []string{"gone"},
		},
	}
	to := map[string]sourceAggregate{
		"github.com|libffi/libffi": {
			ref:  sourceRef{host: "github.com", path: "libffi/libffi", version: "v3.6.0"},
			apks: []string{"libffi"},
		},
		"github.com|kjd/idna": {
			ref:  sourceRef{host: "github.com", path: "kjd/idna", version: "v3.10"},
			apks: []string{"py3-idna"},
		},
		"github.com|new/repo": { // added
			ref:  sourceRef{host: "github.com", path: "new/repo", version: "v1.0"},
			apks: []string{"new"},
		},
	}

	got := diffSources(from, to)

	if len(got.Added) != 1 || got.Added[0].Name != "new/repo" {
		t.Errorf("Added = %+v, want [new/repo]", got.Added)
	}
	if len(got.Removed) != 1 || got.Removed[0].Name != "gone/repo" {
		t.Errorf("Removed = %+v, want [gone/repo]", got.Removed)
	}
	if len(got.Updated) != 1 {
		t.Fatalf("Updated len = %d, want 1: %+v", len(got.Updated), got.Updated)
	}
	u := got.Updated[0]
	if u.Name != "libffi/libffi" || u.From != "v3.5.2" || u.To != "v3.6.0" {
		t.Errorf("Updated[0] = %+v, want libffi/libffi v3.5.2 → v3.6.0", u)
	}
	if u.URL != "https://github.com/libffi/libffi/releases/tag/v3.6.0" {
		t.Errorf("Updated[0].URL = %q, want releases-tag URL for the new version", u.URL)
	}
	if u.CompareURL != "https://github.com/libffi/libffi/compare/v3.5.2...v3.6.0" {
		t.Errorf("Updated[0].CompareURL = %q, want compare URL", u.CompareURL)
	}
	if !reflect.DeepEqual(u.Packages, []string{"libffi"}) {
		t.Errorf("Updated[0].Packages = %v, want [libffi]", u.Packages)
	}
}

func TestDiffSources_UnchangedVersionOmitted(t *testing.T) {
	// Same version on both sides but apk set shifted — should NOT appear in
	// the sources diff (movement is already visible in the packages diff).
	from := map[string]sourceAggregate{
		"github.com|owner/repo": {
			ref:  sourceRef{host: "github.com", path: "owner/repo", version: "v1.0"},
			apks: []string{"apk-a"},
		},
	}
	to := map[string]sourceAggregate{
		"github.com|owner/repo": {
			ref:  sourceRef{host: "github.com", path: "owner/repo", version: "v1.0"},
			apks: []string{"apk-a", "apk-b"},
		},
	}
	got := diffSources(from, to)
	if len(got.Added) != 0 || len(got.Removed) != 0 || len(got.Updated) != 0 {
		t.Errorf("expected empty diff for unchanged version, got %+v", got)
	}
}

func TestDiffSources_EmptyBucketsAreNonNil(t *testing.T) {
	got := diffSources(nil, nil)
	if got.Added == nil || got.Removed == nil || got.Updated == nil {
		t.Errorf("empty buckets should be non-nil for JSON marshal: %+v", got)
	}
}

func TestDiffSources_AddedPackagesSorted(t *testing.T) {
	// Source added on the to-side should have its apks list sorted in the
	// output so JSON consumers get stable ordering.
	to := map[string]sourceAggregate{
		"github.com|owner/repo": {
			ref:  sourceRef{host: "github.com", path: "owner/repo", version: "v1.0"},
			apks: []string{"z-apk", "a-apk", "m-apk"},
		},
	}
	got := diffSources(nil, to)
	if len(got.Added) != 1 {
		t.Fatalf("got %d Added, want 1", len(got.Added))
	}
	want := []string{"a-apk", "m-apk", "z-apk"}
	if !reflect.DeepEqual(got.Added[0].Packages, want) {
		t.Errorf("Packages = %v, want %v", got.Added[0].Packages, want)
	}
}
