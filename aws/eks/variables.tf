variable "region" {
  description = "AWS region to deploy the EKS cluster into."
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes control-plane version. Pinned to 1.35 because the Chainguard charts (notably cluster-autoscaler appVersion 1.35.0 and kube-proxy) target the current EKS default release."
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group. Default sized for the addons in this module — actual usage is ~25m CPU / 650 MiB per node, so anything bigger is waste. Bump if you add workloads."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_min_size" {
  description = "Minimum size of the managed node group."
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum size of the managed node group."
  type        = number
  default     = 5
}

variable "node_group_desired_size" {
  description = "Desired size of the managed node group."
  type        = number
  default     = 3
}

variable "chainguard_org" {
  description = "Chainguard organization name (the path segment in cgr.dev/<org>/charts/...). Also used as the ECR repository prefix for the pull-through cache rule."
  type        = string

  validation {
    condition     = length(var.chainguard_org) > 0
    error_message = "chainguard_org must be set; this module installs charts from oci://cgr.dev/<org>/charts/<name>."
  }
}

variable "chainguard_pull_username" {
  description = "Chainguard registry pull token username, stored in Secrets Manager and used by the ECR pull-through cache rule."
  type        = string
  sensitive   = true
}

variable "chainguard_pull_token" {
  description = "Chainguard registry pull token, stored in Secrets Manager and used by the ECR pull-through cache rule."
  type        = string
  sensitive   = true
}

variable "enable_cert_manager" {
  description = "Install cert-manager."
  type        = bool
  default     = true
}

variable "enable_aws_load_balancer_controller" {
  description = "Install the AWS Load Balancer Controller."
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Install external-dns."
  type        = bool
  default     = true
}

variable "external_dns_domain_filters" {
  description = "Domain filters for external-dns. Only used when enable_external_dns = true."
  type        = list(string)
  default     = []
}

variable "enable_metrics_server" {
  description = "Install metrics-server."
  type        = bool
  default     = true
}

variable "enable_cluster_autoscaler" {
  description = "Install cluster-autoscaler."
  type        = bool
  default     = true
}

variable "enable_kube_state_metrics" {
  description = "Install kube-state-metrics."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to all created AWS resources."
  type        = map(string)
  default     = {}
}
