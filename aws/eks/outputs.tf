output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster, used for IRSA."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA-aware modules to consume."
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID the cluster runs in."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnets
}

output "kubeconfig_command" {
  description = "Run this to populate kubeconfig for the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "ecr_registry" {
  description = "ECR registry host (<account>.dkr.ecr.<region>.amazonaws.com)."
  value       = local.ecr_registry
}

output "ecr_pull_through_prefix" {
  description = "ECR repository prefix the pull-through cache rule uses for cgr.dev."
  value       = aws_ecr_pull_through_cache_rule.chainguard.ecr_repository_prefix
}

output "chainguard_org" {
  description = "Chainguard organization the module pulls images for."
  value       = var.chainguard_org
}
