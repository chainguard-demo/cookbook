output "remediated_repository_key" {
  description = "Key of the Chainguard remediated remote repository."
  value       = artifactory_remote_pypi_repository.remediated.key
}

output "chainguard_repository_key" {
  description = "Key of the Chainguard standard remote repository."
  value       = artifactory_remote_pypi_repository.chainguard.key
}

output "public_repository_key" {
  description = "Key of the upstream PyPI remote repository."
  value       = artifactory_remote_pypi_repository.public.key
}

output "virtual_repository_key" {
  description = "Key of the virtual repository aggregating remediated, chainguard, and public in that order."
  value       = artifactory_virtual_pypi_repository.all.key
}
