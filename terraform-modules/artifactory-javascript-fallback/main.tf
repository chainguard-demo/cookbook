locals {
  chainguard_key = "${var.name}-js-chainguard"
  public_key     = "${var.name}-js-public"
  virtual_key    = "${var.name}-js-all"

  chainguard_url = "${var.chainguard_libraries_url}/${var.chainguard_index_path}/"
}

# Remote: Chainguard npm index (highest priority).
resource "artifactory_remote_npm_repository" "chainguard" {
  key         = local.chainguard_key
  url         = local.chainguard_url
  username    = var.chainguard_username
  password    = var.chainguard_password
  description = "${var.description} - Chainguard index"
  # Chainguard's npm index 302s to Cloudflare R2 pre-signed URLs. Default URL
  # normalization re-encodes the redirect target and breaks the AWS signature,
  # producing 404s on tarball downloads.
  disable_url_normalization = true
  # Per Chainguard docs: the upstream rejects HEAD requests against tarball
  # paths; without this, Artifactory's pre-flight HEAD fails and the GET is
  # never attempted, so tarball fetches return 404.
  bypass_head_requests = true
  project_key          = var.project_key != "" ? var.project_key : null
}

# Remote: Upstream public npm registry (fallback for packages not in Chainguard).
resource "artifactory_remote_npm_repository" "public" {
  key         = local.public_key
  url         = var.npm_registry_url
  description = "Public npm registry fallback"
  project_key = var.project_key != "" ? var.project_key : null
}

# Virtual: aggregates the two remotes with Chainguard first, public npm fallback.
resource "artifactory_virtual_npm_repository" "all" {
  key         = local.virtual_key
  description = "${var.description} - virtual aggregator"
  repositories = [
    artifactory_remote_npm_repository.chainguard.key,
    artifactory_remote_npm_repository.public.key,
  ]
  default_deployment_repo = var.default_deployment_repo != "" ? var.default_deployment_repo : null
  project_key             = var.project_key != "" ? var.project_key : null
}
