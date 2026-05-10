data "aws_availability_zones" "available" {
  state = "available"
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

  enable_cluster_creator_admin_permissions = true

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
