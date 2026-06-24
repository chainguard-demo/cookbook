package diff

import "strings"

// ecosystemFromPurl extracts the ecosystem from a purl like
// "pkg:apk/wolfi/libcrypto3@3.6.3-r2?arch=...". Returns "" if the purl
// doesn't parse cleanly.
func ecosystemFromPurl(purl string) string {
	const prefix = "pkg:"
	if !strings.HasPrefix(purl, prefix) {
		return ""
	}
	rest := purl[len(prefix):]
	if i := strings.IndexAny(rest, "/@?#"); i >= 0 {
		return rest[:i]
	}
	return rest
}

// sourceRef is a parsed github/gitlab purl: which host, which repo path,
// which version. The path can contain slashes (gitlab subgroups) so we keep
// it as a single string rather than splitting into owner/repo.
type sourceRef struct {
	host    string // "github.com" or "gitlab.com"
	path    string // e.g. "kjd/idna" or "gnutools/glibc"
	version string // raw, as it appears in the purl (may be a tag or a SHA)
}

func parseSourcePurl(purl string) (sourceRef, bool) {
	var prefix, host string
	switch {
	case strings.HasPrefix(purl, "pkg:github/"):
		prefix, host = "pkg:github/", "github.com"
	case strings.HasPrefix(purl, "pkg:gitlab/"):
		prefix, host = "pkg:gitlab/", "gitlab.com"
	default:
		return sourceRef{}, false
	}
	rest := purl[len(prefix):]
	var path, version string
	if at := strings.Index(rest, "@"); at >= 0 {
		path = rest[:at]
		version = rest[at+1:]
		if i := strings.IndexAny(version, "?#"); i >= 0 {
			version = version[:i]
		}
	} else {
		path = rest
		if i := strings.IndexAny(path, "?#"); i >= 0 {
			path = path[:i]
		}
	}
	if path == "" {
		return sourceRef{}, false
	}
	return sourceRef{host: host, path: path, version: version}, true
}

// isSourcePurl is the prefix check used during SBOM walking — true for any
// purl we know how to build URLs for.
func isSourcePurl(purl string) bool {
	return strings.HasPrefix(purl, "pkg:github/") || strings.HasPrefix(purl, "pkg:gitlab/")
}

// sourceURL renders the per-version "commit or tag" URL for one source ref.
// github uses /releases/tag/<tag> and /commit/<sha>; gitlab uses /-/tags/<tag>
// and /-/commit/<sha>. SHA detection is a strict 40-char hex check.
func (s sourceRef) sourceURL() string {
	if s.version == "" || s.path == "" {
		return ""
	}
	switch s.host {
	case "github.com":
		if looksLikeGitSHA(s.version) {
			return "https://github.com/" + s.path + "/commit/" + s.version
		}
		return "https://github.com/" + s.path + "/releases/tag/" + s.version
	case "gitlab.com":
		if looksLikeGitSHA(s.version) {
			return "https://gitlab.com/" + s.path + "/-/commit/" + s.version
		}
		return "https://gitlab.com/" + s.path + "/-/tags/" + s.version
	}
	return ""
}

func (s sourceRef) compareURLTo(toVersion string) string {
	if s.version == "" || toVersion == "" || s.path == "" {
		return ""
	}
	switch s.host {
	case "github.com":
		return "https://github.com/" + s.path + "/compare/" + s.version + "..." + toVersion
	case "gitlab.com":
		return "https://gitlab.com/" + s.path + "/-/compare/" + s.version + "..." + toVersion
	}
	return ""
}

// looksLikeGitSHA matches a 40-char lowercase hex string — a git commit SHA.
// Used to decide whether a github/gitlab purl version is a commit or a tag.
func looksLikeGitSHA(s string) bool {
	if len(s) != 40 {
		return false
	}
	for _, c := range s {
		switch {
		case c >= '0' && c <= '9':
		case c >= 'a' && c <= 'f':
		default:
			return false
		}
	}
	return true
}
