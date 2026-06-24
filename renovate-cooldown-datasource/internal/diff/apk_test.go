package diff

import (
	"reflect"
	"testing"
)

// apkPkg is a tiny constructor used throughout the apk + sources tests to
// keep fixture literals readable.
func apkPkg(id, name, version string) sbomPackage {
	return sbomPackage{
		ID:      id,
		Name:    name,
		Version: version,
		Purl:    "pkg:apk/wolfi/" + name + "@" + version + "?arch=x86_64&distro=wolfi",
	}
}

// originPkg is the duplicate origin entry Chainguard SBOMs publish for each
// apk (no `distro=` qualifier — uses `origin=` instead).
func originPkg(id, name, version string) sbomPackage {
	return sbomPackage{
		ID:      id,
		Name:    name,
		Version: version,
		Purl:    "pkg:apk/wolfi/" + name + "@" + version + "?arch=x86_64&origin=" + name,
	}
}

func TestCollectAPKEntries(t *testing.T) {
	s := &sbom{
		Packages: []sbomPackage{
			apkPkg("SPDXRef-libcrypto3", "libcrypto3", "3.6.3-r2"),
			originPkg("SPDXRef-libcrypto3-origin", "libcrypto3", "3.6.3-r2"),
			{ID: "SPDXRef-cpython", Name: "cpython", Version: "3.14.6", Purl: "pkg:github/python/cpython@v3.14.6"},
			{ID: "SPDXRef-no-purl", Name: "weird", Version: "0", Purl: ""},
		},
	}
	got := collectAPKEntries(s)
	// Both apk entries should be returned (dedup happens later in indexAPK);
	// the github source and the purl-less entry should be filtered out.
	if len(got) != 2 {
		t.Fatalf("got %d entries, want 2: %+v", len(got), got)
	}
	for _, e := range got {
		if ecosystemFromPurl(e.pkg.Purl) != "apk" {
			t.Errorf("non-apk entry leaked through: %+v", e)
		}
	}
}

func TestIndexAPK_PrefersCanonical(t *testing.T) {
	tests := []struct {
		name     string
		entries  []apkEntry
		wantPurl string // expected purl of the entry kept for "libcrypto3"
	}{
		{
			name: "origin first then canonical",
			entries: []apkEntry{
				{pkg: originPkg("a", "libcrypto3", "3.6.3-r2")},
				{pkg: apkPkg("b", "libcrypto3", "3.6.3-r2")},
			},
			wantPurl: apkPkg("b", "libcrypto3", "3.6.3-r2").Purl,
		},
		{
			name: "canonical first then origin",
			entries: []apkEntry{
				{pkg: apkPkg("a", "libcrypto3", "3.6.3-r2")},
				{pkg: originPkg("b", "libcrypto3", "3.6.3-r2")},
			},
			wantPurl: apkPkg("a", "libcrypto3", "3.6.3-r2").Purl,
		},
		{
			name: "only origin",
			entries: []apkEntry{
				{pkg: originPkg("a", "libcrypto3", "3.6.3-r2")},
			},
			wantPurl: originPkg("a", "libcrypto3", "3.6.3-r2").Purl,
		},
		{
			name: "only canonical",
			entries: []apkEntry{
				{pkg: apkPkg("a", "libcrypto3", "3.6.3-r2")},
			},
			wantPurl: apkPkg("a", "libcrypto3", "3.6.3-r2").Purl,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			m := indexAPK(tc.entries)
			got, ok := m["libcrypto3"]
			if !ok {
				t.Fatalf("libcrypto3 missing from index")
			}
			if got.pkg.Purl != tc.wantPurl {
				t.Errorf("kept purl = %q, want %q", got.pkg.Purl, tc.wantPurl)
			}
		})
	}
}

func TestDiffAPKPackages(t *testing.T) {
	from := []apkEntry{
		{pkg: apkPkg("1", "libcrypto3", "3.6.3-r0")},
		{pkg: apkPkg("2", "ca-certificates-bundle", "20251006-r0")},
		{pkg: apkPkg("3", "removed-pkg", "1.0-r0")},
	}
	to := []apkEntry{
		{pkg: apkPkg("1", "libcrypto3", "3.6.3-r2")},          // updated
		{pkg: apkPkg("2", "ca-certificates-bundle", "20251006-r0")}, // unchanged
		{pkg: apkPkg("4", "added-pkg", "2.0-r0")},             // added
	}

	got := diffAPKPackages(from, to)

	if len(got.Added) != 1 || got.Added[0].Name != "added-pkg" || got.Added[0].Version != "2.0-r0" || got.Added[0].Ecosystem != "apk" {
		t.Errorf("Added = %+v, want [{added-pkg 2.0-r0 apk ...}]", got.Added)
	}
	if len(got.Removed) != 1 || got.Removed[0].Name != "removed-pkg" || got.Removed[0].Version != "1.0-r0" {
		t.Errorf("Removed = %+v, want [{removed-pkg 1.0-r0 apk ...}]", got.Removed)
	}
	if len(got.Updated) != 1 {
		t.Fatalf("Updated len = %d, want 1: %+v", len(got.Updated), got.Updated)
	}
	if got.Updated[0].Name != "libcrypto3" || got.Updated[0].From != "3.6.3-r0" || got.Updated[0].To != "3.6.3-r2" {
		t.Errorf("Updated[0] = %+v, want libcrypto3 3.6.3-r0 → 3.6.3-r2", got.Updated[0])
	}
	if got.Updated[0].Purl == "" || got.Updated[0].Purl != to[0].pkg.Purl {
		t.Errorf("Updated[0].Purl = %q, want to-side purl %q", got.Updated[0].Purl, to[0].pkg.Purl)
	}
}

func TestDiffAPKPackages_EmptyBuckets(t *testing.T) {
	// Both sides identical → all buckets empty (non-nil slices, for JSON shape).
	from := []apkEntry{{pkg: apkPkg("1", "libcrypto3", "3.6.3-r2")}}
	to := []apkEntry{{pkg: apkPkg("1", "libcrypto3", "3.6.3-r2")}}
	got := diffAPKPackages(from, to)
	if len(got.Added) != 0 || len(got.Removed) != 0 || len(got.Updated) != 0 {
		t.Errorf("expected empty buckets, got %+v", got)
	}
	// Slices must be initialised so JSON marshals to [] not null.
	if got.Added == nil || got.Removed == nil || got.Updated == nil {
		t.Error("buckets should be non-nil even when empty")
	}
}

func TestDiffAPKPackages_OutputSorted(t *testing.T) {
	// Names are processed in sorted order, so the Added/Removed/Updated
	// slices land in alphabetical order even if input was scrambled.
	from := []apkEntry{
		{pkg: apkPkg("1", "zebra", "1.0")},
		{pkg: apkPkg("2", "alpha", "1.0")},
	}
	to := []apkEntry{
		{pkg: apkPkg("3", "zebra", "2.0")},
		{pkg: apkPkg("4", "alpha", "2.0")},
	}
	got := diffAPKPackages(from, to)
	names := []string{got.Updated[0].Name, got.Updated[1].Name}
	want := []string{"alpha", "zebra"}
	if !reflect.DeepEqual(names, want) {
		t.Errorf("Updated names = %v, want %v", names, want)
	}
}
