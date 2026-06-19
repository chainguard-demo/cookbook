locals {
  remediated_key = "${var.name}-py-chainguard-remediated"
  chainguard_key = "${var.name}-py-chainguard"
  public_key     = "${var.name}-py-public"
  virtual_key    = "${var.name}-py-all"

  remediated_url = "${var.chainguard_libraries_url}/${var.remediated_index_path}/"
  chainguard_url = "${var.chainguard_libraries_url}/${var.chainguard_index_path}/"
}

# Remote: Chainguard remediated Python index (highest priority).
resource "artifactory_remote_pypi_repository" "remediated" {
  key                          = local.remediated_key
  url                          = local.remediated_url
  username                     = var.chainguard_username
  password                     = var.chainguard_password
  description                  = "${var.description} - remediated index"
  pypi_registry_url            = local.remediated_url
  block_mismatching_mime_types = false
  # Required: wheels are served via a 302 redirect to a Cloudflare R2 pre-signed
  # URL; default URL normalization re-encodes the redirect target and breaks
  # the AWS signature, causing 404s on wheel downloads.
  disable_url_normalization = true
  project_key               = var.project_key != "" ? var.project_key : null
}

# Remote: Chainguard standard Python index.
resource "artifactory_remote_pypi_repository" "chainguard" {
  key                          = local.chainguard_key
  url                          = local.chainguard_url
  username                     = var.chainguard_username
  password                     = var.chainguard_password
  description                  = "${var.description} - standard index"
  pypi_registry_url            = local.chainguard_url
  block_mismatching_mime_types = false
  # See note on remediated remote: required for R2 pre-signed URL redirects.
  disable_url_normalization = true
  project_key               = var.project_key != "" ? var.project_key : null
}

# Remote: Upstream public PyPI (fallback for packages not in Chainguard).
resource "artifactory_remote_pypi_repository" "public" {
  key               = local.public_key
  url               = "https://files.pythonhosted.org/"
  description       = "Public PyPI fallback"
  pypi_registry_url = "https://pypi.org"
  project_key       = var.project_key != "" ? var.project_key : null
}

# Virtual: aggregates the three remotes with the requested fallback order.
resource "artifactory_virtual_pypi_repository" "all" {
  key         = local.virtual_key
  description = "${var.description} - virtual aggregator"
  repositories = [
    artifactory_remote_pypi_repository.remediated.key,
    artifactory_remote_pypi_repository.chainguard.key,
    artifactory_remote_pypi_repository.public.key,
  ]
  default_deployment_repo = var.default_deployment_repo != "" ? var.default_deployment_repo : null
  project_key             = var.project_key != "" ? var.project_key : null
}
