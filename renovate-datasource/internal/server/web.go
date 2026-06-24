package server

import (
	_ "embed"
	"html/template"
	"net/http"
)

//go:embed templates/diff.html
var diffPageHTML string

//go:embed templates/diff.css
var diffPageCSS string

//go:embed templates/diff.js
var diffPageJS string

// diffPageTemplate is parsed once at startup. The template uses html/template's
// JS-context escaping, so the per-request repo/ref values we substitute into
// the inline <script> block come out as properly-quoted JavaScript string
// literals. The CSS and JS bodies are embedded at build time and rendered as
// template.CSS / template.JS so html/template treats them as already-safe
// content rather than re-escaping them.
var diffPageTemplate = template.Must(template.New("diff").Parse(diffPageHTML))

type diffPageData struct {
	Repo, OldRef, NewRef string
	// Title is the fully-qualified image path displayed in the page header
	// and the browser tab — "cgr.dev/<org>/<repo>" when the org is known,
	// just "<repo>" otherwise.
	Title string
	// ConsoleURL is the Chainguard console "versions" page for this repo,
	// rendered as a link wrapping Title in the page header. Empty if the
	// server wasn't configured with an org name.
	ConsoleURL string
	CSS        template.CSS
	JS         template.JS
}

// handleDiffPage serves the HTML shell that fetches /v1/diff client-side and
// renders it with a spinner while the API call is in flight.
func (s *Server) handleDiffPage(w http.ResponseWriter, r *http.Request) {
	repo := r.PathValue("repo")
	oldRef := r.PathValue("oldRef")
	newRef := r.PathValue("newRef")

	if !repoNamePattern.MatchString(repo) {
		writeAPIError(w, http.StatusBadRequest, "The repo name isn't a valid OCI repository path.")
		return
	}
	if !validRef(oldRef) {
		writeAPIError(w, http.StatusBadRequest, "The 'from' ref isn't a valid OCI tag or sha256 digest.")
		return
	}
	if !validRef(newRef) {
		writeAPIError(w, http.StatusBadRequest, "The 'to' ref isn't a valid OCI tag or sha256 digest.")
		return
	}

	data := diffPageData{
		Repo:       repo,
		OldRef:     oldRef,
		NewRef:     newRef,
		Title:      pageTitle(s.orgName, repo),
		ConsoleURL: consoleURL(s.orgName, repo),
		CSS:        template.CSS(diffPageCSS),
		JS:         template.JS(diffPageJS),
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := diffPageTemplate.Execute(w, data); err != nil {
		s.log.ErrorContext(r.Context(), "rendering diff page", "err", err)
	}
}

// pageTitle returns the displayed image path. When an org is configured we
// surface the full pullable reference; otherwise we fall back to the bare
// repo name (the diff page still works, the link to the console is just
// omitted upstream).
func pageTitle(orgName, repo string) string {
	if orgName == "" {
		return repo
	}
	return "cgr.dev/" + orgName + "/" + repo
}

// consoleURL builds the Chainguard console URL for a repo within an org.
// Returns "" when orgName is empty so the template can omit the link.
// repo is already validated against repoNamePattern (lowercase + slashes
// only) and orgName is the value the operator configured at startup, so
// neither needs additional escaping for the path segments.
func consoleURL(orgName, repo string) string {
	if orgName == "" {
		return ""
	}
	return "https://console.chainguard.dev/org/" + orgName + "/images/organization/image/" + repo + "/versions"
}
