locals {
  public_key = "${var.name}-js-public"
}

# Remote: npm registry proxy (defaults to upstream npm; can point at Chainguard).
resource "artifactory_remote_npm_repository" "public" {
  key         = local.public_key
  url         = var.npm_registry_url
  description = var.description
  username    = var.username != "" ? var.username : null
  password    = var.password != "" ? var.password : null
  # Chainguard's npm index 302s to Cloudflare R2 pre-signed URLs. Default URL
  # normalization re-encodes the redirect target and breaks the AWS signature,
  # producing 404s on tarball downloads.
  disable_url_normalization = true
  # The upstream rejects HEAD requests against tarball paths; without this,
  # Artifactory's pre-flight HEAD fails and the GET is never attempted, so
  # tarball fetches return 404.
  bypass_head_requests = true
  project_key          = var.project_key != "" ? var.project_key : null
}
