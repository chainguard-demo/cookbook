output "remediated_repository_name" {
  description = "Name of the Chainguard remediated PyPI proxy repository."
  value       = nexus_repository_pypi_proxy.remediated.name
}

output "chainguard_repository_name" {
  description = "Name of the Chainguard standard PyPI proxy repository."
  value       = nexus_repository_pypi_proxy.chainguard.name
}

output "public_repository_name" {
  description = "Name of the upstream public PyPI proxy repository."
  value       = nexus_repository_pypi_proxy.public.name
}

output "group_repository_name" {
  description = "Name of the PyPI group repository aggregating remediated, chainguard, and public in that order."
  value       = nexus_repository_pypi_group.all.name
}
