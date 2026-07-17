data "aws_availability_zones" "available" {
  state = "available"
}

# The identity running `terraform apply` also drives the helm/kubernetes
# providers, which install cluster-scoped CRDs (vpc-cni's ENIConfig, the
# cert-manager CRDs, etc.). That needs cluster-admin RBAC.
#
# `aws_caller_identity.arn` is the STS *session* ARN (e.g. for SSO:
# arn:aws:sts::<acct>:assumed-role/AWSReservedSSO_.../<user>), which does not
# match an EKS access entry. `aws_iam_session_context` resolves it back to the
# underlying IAM role ARN, which we grant an access entry below. This is more
# reliable than `enable_cluster_creator_admin_permissions`, which keys off the
# raw session ARN and silently leaves assumed-role/SSO callers without admin.
# (aws_caller_identity.current is declared in ecr.tf.)
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# Single random suffix shared by every AWS resource the module names —
# the EKS cluster, IAM roles, secrets, ECR pull-through prefix, etc.
# Keepers tie regeneration to the input cluster_name, so the value is
# stable across applies as long as that input doesn't change.
resource "random_id" "this" {
  byte_length = 3

  keepers = {
    cluster_name = var.cluster_name
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  suffix       = random_id.this.hex
  cluster_name = "${var.cluster_name}-${local.suffix}"

  common_tags = merge(
    {
      "managed-by" = "terraform"
      "cluster"    = local.cluster_name
    },
    var.tags,
  )
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = 1
    "karpenter.sh/discovery"                      = local.cluster_name
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  tags = local.common_tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.13"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Grant the terraform-running identity (resolved to its underlying IAM role,
  # see data.aws_iam_session_context above) cluster-admin so the helm provider
  # can create CRDs. We do this explicitly instead of via
  # enable_cluster_creator_admin_permissions so assumed-role/SSO callers work.
  authentication_mode = "API_AND_CONFIG_MAP"

  access_entries = {
    terraform_runner = {
      principal_arn = data.aws_iam_session_context.current.issuer_arn

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # All networking, DNS, and storage addons (kube-proxy, vpc-cni, coredns,
  # aws-ebs-csi-driver) are installed via Chainguard Helm charts in
  # addons.tf. Skip AWS's bootstrap of the default DaemonSets and don't
  # create any EKS-managed addons — there's nothing here to collide with.
  bootstrap_self_managed_addons = false
  cluster_addons                = {}

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types

      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size

      iam_role_additional_policies = {
        ecr_pull_through_cache = aws_iam_policy.ecr_pull_through_cache.arn
      }
    }
  }

  tags = local.common_tags
}
