output "remediated_repository_name" {
  description = "Name of the Chainguard remediated Maven proxy repository."
  value       = nexus_repository_maven_proxy.remediated.name
}

output "chainguard_repository_name" {
  description = "Name of the Chainguard standard Maven proxy repository."
  value       = nexus_repository_maven_proxy.chainguard.name
}

output "public_repository_name" {
  description = "Name of the upstream Maven Central proxy repository."
  value       = nexus_repository_maven_proxy.public.name
}

output "group_repository_name" {
  description = "Name of the Maven group repository aggregating remediated, chainguard, and public in that order."
  value       = nexus_repository_maven_group.all.name
}
