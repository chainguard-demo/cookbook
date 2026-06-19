locals {
  remediated_key = "${var.name}-java-chainguard-remediated"
  chainguard_key = "${var.name}-java-chainguard"
  public_key     = "${var.name}-java-public"
  virtual_key    = "${var.name}-java-all"

  remediated_url = "${var.chainguard_libraries_url}/${var.remediated_index_path}/"
  chainguard_url = "${var.chainguard_libraries_url}/${var.chainguard_index_path}/"
}

# Remote: Chainguard remediated Java index (highest priority).
resource "artifactory_remote_maven_repository" "remediated" {
  key                          = local.remediated_key
  url                          = local.remediated_url
  username                     = var.chainguard_username
  password                     = var.chainguard_password
  description                  = "${var.description} - remediated index"
  block_mismatching_mime_types = false
  # Per Chainguard docs: Maven snapshot handling must be off for the
  # Chainguard remote so Artifactory does not attempt snapshot resolution.
  handle_snapshots = false
  project_key      = var.project_key != "" ? var.project_key : null
}

# Remote: Chainguard standard Java index.
resource "artifactory_remote_maven_repository" "chainguard" {
  key                          = local.chainguard_key
  url                          = local.chainguard_url
  username                     = var.chainguard_username
  password                     = var.chainguard_password
  description                  = "${var.description} - standard index"
  block_mismatching_mime_types = false
  handle_snapshots             = false
  project_key                  = var.project_key != "" ? var.project_key : null
}

# Remote: Upstream Maven Central (fallback for artifacts not in Chainguard).
resource "artifactory_remote_maven_repository" "public" {
  key              = local.public_key
  url              = var.maven_central_url
  description      = "Maven Central fallback"
  handle_snapshots = false
  project_key      = var.project_key != "" ? var.project_key : null
}

# Virtual: aggregates the three remotes with the requested fallback order.
resource "artifactory_virtual_maven_repository" "all" {
  key         = local.virtual_key
  description = "${var.description} - virtual aggregator"
  repositories = [
    artifactory_remote_maven_repository.remediated.key,
    artifactory_remote_maven_repository.chainguard.key,
    artifactory_remote_maven_repository.public.key,
  ]
  default_deployment_repo = var.default_deployment_repo != "" ? var.default_deployment_repo : null
  project_key             = var.project_key != "" ? var.project_key : null
}
