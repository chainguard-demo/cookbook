output "public_repository_name" {
  description = "Name of the npm proxy repository."
  value       = nexus_repository_npm_proxy.public.name
}
