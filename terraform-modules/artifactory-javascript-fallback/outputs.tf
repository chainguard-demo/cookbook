output "chainguard_repository_key" {
  description = "Key of the Chainguard npm remote repository."
  value       = artifactory_remote_npm_repository.chainguard.key
}

output "public_repository_key" {
  description = "Key of the upstream public npm remote repository."
  value       = artifactory_remote_npm_repository.public.key
}

output "virtual_repository_key" {
  description = "Key of the virtual repository aggregating chainguard and public in that order."
  value       = artifactory_virtual_npm_repository.all.key
}
