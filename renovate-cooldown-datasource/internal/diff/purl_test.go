package diff

import "testing"

func TestEcosystemFromPurl(t *testing.T) {
	tests := []struct {
		name string
		purl string
		want string
	}{
		{"apk with qualifiers", "pkg:apk/wolfi/libcrypto3@3.6.3-r2?arch=x86_64&distro=wolfi", "apk"},
		{"github tag", "pkg:github/kjd/idna@v3.10", "github"},
		{"gitlab subgroup", "pkg:gitlab/group/sub/repo@v1.0", "gitlab"},
		{"bare prefix", "pkg:apk", "apk"},
		{"missing pkg: prefix", "apk/wolfi/libcrypto3", ""},
		{"empty", "", ""},
		{"just pkg:", "pkg:", ""},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := ecosystemFromPurl(tc.purl); got != tc.want {
				t.Errorf("ecosystemFromPurl(%q) = %q, want %q", tc.purl, got, tc.want)
			}
		})
	}
}

func TestIsSourcePurl(t *testing.T) {
	tests := []struct {
		purl string
		want bool
	}{
		{"pkg:github/owner/repo@v1.0", true},
		{"pkg:gitlab/group/repo@v1.0", true},
		{"pkg:apk/wolfi/libcrypto3@3.6.3-r2", false},
		{"pkg:githubsomething/x", false},
		{"", false},
	}
	for _, tc := range tests {
		if got := isSourcePurl(tc.purl); got != tc.want {
			t.Errorf("isSourcePurl(%q) = %v, want %v", tc.purl, got, tc.want)
		}
	}
}

func TestParseSourcePurl(t *testing.T) {
	tests := []struct {
		name    string
		purl    string
		want    sourceRef
		wantErr bool
	}{
		{
			name: "github tag",
			purl: "pkg:github/kjd/idna@v3.10",
			want: sourceRef{host: "github.com", path: "kjd/idna", version: "v3.10"},
		},
		{
			name: "github sha with qualifiers",
			purl: "pkg:github/libffi/libffi@3a7580da73b7f16f275277316d00e3497cbb5a3a?type=commit",
			want: sourceRef{host: "github.com", path: "libffi/libffi", version: "3a7580da73b7f16f275277316d00e3497cbb5a3a"},
		},
		{
			name: "gitlab subgroup path",
			purl: "pkg:gitlab/group/subgroup/project@1.2.3",
			want: sourceRef{host: "gitlab.com", path: "group/subgroup/project", version: "1.2.3"},
		},
		{
			name: "github with fragment instead of qualifier",
			purl: "pkg:github/owner/repo@v1.0#frag",
			want: sourceRef{host: "github.com", path: "owner/repo", version: "v1.0"},
		},
		{
			name: "github no version",
			purl: "pkg:github/owner/repo",
			want: sourceRef{host: "github.com", path: "owner/repo", version: ""},
		},
		{
			name: "github no version with qualifiers",
			purl: "pkg:github/owner/repo?vcs_url=https://github.com/owner/repo.git",
			want: sourceRef{host: "github.com", path: "owner/repo", version: ""},
		},
		{
			name:    "wrong scheme",
			purl:    "pkg:apk/wolfi/libcrypto3@3.6.3-r2",
			wantErr: true,
		},
		{
			name:    "github empty path",
			purl:    "pkg:github/@v1.0",
			wantErr: true,
		},
		{
			name:    "github empty path no version",
			purl:    "pkg:github/",
			wantErr: true,
		},
		{
			name:    "empty",
			purl:    "",
			wantErr: true,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := parseSourcePurl(tc.purl)
			if ok == tc.wantErr {
				t.Fatalf("parseSourcePurl(%q) ok=%v wantErr=%v", tc.purl, ok, tc.wantErr)
			}
			if tc.wantErr {
				return
			}
			if got != tc.want {
				t.Errorf("parseSourcePurl(%q) = %+v, want %+v", tc.purl, got, tc.want)
			}
		})
	}
}

func TestLooksLikeGitSHA(t *testing.T) {
	tests := []struct {
		s    string
		want bool
	}{
		{"3a7580da73b7f16f275277316d00e3497cbb5a3a", true},
		{"3A7580DA73B7F16F275277316D00E3497CBB5A3A", false}, // uppercase rejected
		{"3a7580da73b7f16f275277316d00e3497cbb5a3", false},  // 39 chars
		{"3a7580da73b7f16f275277316d00e3497cbb5a3aa", false}, // 41 chars
		{"v3.10", false},                                     // tag-shaped
		{"", false},
		{"3a7580da73b7f16f275277316d00e3497cbb5z3a", false},  // contains 'z'
	}
	for _, tc := range tests {
		if got := looksLikeGitSHA(tc.s); got != tc.want {
			t.Errorf("looksLikeGitSHA(%q) = %v, want %v", tc.s, got, tc.want)
		}
	}
}

func TestSourceRefURLs(t *testing.T) {
	tests := []struct {
		name        string
		ref         sourceRef
		wantSource  string
		toVersion   string
		wantCompare string
	}{
		{
			name:        "github tag",
			ref:         sourceRef{host: "github.com", path: "kjd/idna", version: "v3.10"},
			wantSource:  "https://github.com/kjd/idna/releases/tag/v3.10",
			toVersion:   "v3.11",
			wantCompare: "https://github.com/kjd/idna/compare/v3.10...v3.11",
		},
		{
			name:        "github sha",
			ref:         sourceRef{host: "github.com", path: "libffi/libffi", version: "3a7580da73b7f16f275277316d00e3497cbb5a3a"},
			wantSource:  "https://github.com/libffi/libffi/commit/3a7580da73b7f16f275277316d00e3497cbb5a3a",
			toVersion:   "v3.6.0",
			wantCompare: "https://github.com/libffi/libffi/compare/3a7580da73b7f16f275277316d00e3497cbb5a3a...v3.6.0",
		},
		{
			name:        "gitlab tag",
			ref:         sourceRef{host: "gitlab.com", path: "group/sub/proj", version: "1.2.3"},
			wantSource:  "https://gitlab.com/group/sub/proj/-/tags/1.2.3",
			toVersion:   "1.3.0",
			wantCompare: "https://gitlab.com/group/sub/proj/-/compare/1.2.3...1.3.0",
		},
		{
			name:       "empty version yields empty URL",
			ref:        sourceRef{host: "github.com", path: "owner/repo", version: ""},
			wantSource: "",
		},
		{
			name:       "unknown host yields empty URL",
			ref:        sourceRef{host: "bitbucket.org", path: "owner/repo", version: "v1.0"},
			wantSource: "",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.ref.sourceURL(); got != tc.wantSource {
				t.Errorf("sourceURL() = %q, want %q", got, tc.wantSource)
			}
			if tc.toVersion != "" {
				if got := tc.ref.compareURLTo(tc.toVersion); got != tc.wantCompare {
					t.Errorf("compareURLTo(%q) = %q, want %q", tc.toVersion, got, tc.wantCompare)
				}
			}
		})
	}
}
