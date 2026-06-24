package diff

import (
	"sort"
	"strings"
)

// apkEntry is one apk-ecosystem package from an SBOM. Source-repo info comes
// from collectSources instead; this struct is intentionally minimal.
type apkEntry struct {
	pkg sbomPackage
}

// collectAPKEntries returns every apk-ecosystem package in the SBOM.
func collectAPKEntries(s *sbom) []apkEntry {
	out := make([]apkEntry, 0)
	for _, p := range s.Packages {
		if ecosystemFromPurl(p.Purl) != "apk" {
			continue
		}
		out = append(out, apkEntry{pkg: p})
	}
	return out
}

// diffAPKPackages joins from/to apk entries on package name and emits the
// add/remove/update buckets.
func diffAPKPackages(from, to []apkEntry) Packages {
	fromByName := indexAPK(from)
	toByName := indexAPK(to)

	names := make([]string, 0, len(fromByName)+len(toByName))
	for n := range fromByName {
		names = append(names, n)
	}
	for n := range toByName {
		if _, seen := fromByName[n]; !seen {
			names = append(names, n)
		}
	}
	sort.Strings(names)

	out := Packages{
		Added:   []PackageEntry{},
		Removed: []PackageEntry{},
		Updated: []PackageDelta{},
	}
	for _, n := range names {
		fe, fok := fromByName[n]
		te, tok := toByName[n]
		switch {
		case !fok && tok:
			out.Added = append(out.Added, PackageEntry{
				Name:      te.pkg.Name,
				Version:   te.pkg.Version,
				Ecosystem: "apk",
				Purl:      te.pkg.Purl,
			})
		case fok && !tok:
			out.Removed = append(out.Removed, PackageEntry{
				Name:      fe.pkg.Name,
				Version:   fe.pkg.Version,
				Ecosystem: "apk",
				Purl:      fe.pkg.Purl,
			})
		case fok && tok && fe.pkg.Version != te.pkg.Version:
			out.Updated = append(out.Updated, PackageDelta{
				Name:      n,
				From:      fe.pkg.Version,
				To:        te.pkg.Version,
				Ecosystem: "apk",
				Purl:      te.pkg.Purl,
			})
		}
	}
	return out
}

// indexAPK keys apk entries by package name. Chainguard SBOMs list each apk
// twice — once as the canonical install entry (purl qualifier `distro=`) and
// once as an origin/subpackage entry (`origin=`). We prefer the canonical
// entry when both are present so subsequent joins line up with the same
// variant that carries GENERATED_FROM relationships in collectSources.
func indexAPK(entries []apkEntry) map[string]apkEntry {
	m := make(map[string]apkEntry, len(entries))
	for _, e := range entries {
		existing, exists := m[e.pkg.Name]
		if exists && isCanonicalAPKPurl(existing.pkg.Purl) && !isCanonicalAPKPurl(e.pkg.Purl) {
			continue
		}
		m[e.pkg.Name] = e
	}
	return m
}

// isCanonicalAPKPurl reports whether the purl is the canonical apk install
// entry (carries the `distro=` qualifier) rather than the origin/subpackage
// duplicate (`origin=`).
func isCanonicalAPKPurl(purl string) bool {
	return strings.Contains(purl, "distro=")
}
