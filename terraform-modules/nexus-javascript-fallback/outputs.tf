output "chainguard_repository_name" {
  description = "Name of the Chainguard npm proxy repository."
  value       = nexus_repository_npm_proxy.chainguard.name
}

output "public_repository_name" {
  description = "Name of the upstream public npm proxy repository."
  value       = nexus_repository_npm_proxy.public.name
}

output "group_repository_name" {
  description = "Name of the npm group repository aggregating chainguard and public in that order."
  value       = nexus_repository_npm_group.all.name
}
