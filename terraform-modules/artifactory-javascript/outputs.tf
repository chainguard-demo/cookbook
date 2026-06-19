output "public_repository_key" {
  description = "Key of the upstream npm remote repository."
  value       = artifactory_remote_npm_repository.public.key
}
