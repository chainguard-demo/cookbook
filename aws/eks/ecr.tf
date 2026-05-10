data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"

  # Per-cluster suffix on the ECR prefix keeps multiple cluster modules
  # from fighting over the same `chainguard` prefix in one account.
  # Shares the random_id with the cluster name and every other AWS
  # resource so one suffix uniquely identifies this deployment.
  ecr_prefix = "chainguard-${local.suffix}"

  # The path under the ECR host that maps via pull-through to cgr.dev.
  # ECR strips the prefix; the chainguard_org segment is what reaches
  # cgr.dev, so it must be present on both sides.
  #
  # Reference `aws_ecr_pull_through_cache_rule.chainguard.ecr_repository_prefix`
  # rather than `local.ecr_prefix` directly: the resource attribute carries
  # an implicit dependency on the rule being created, which propagates
  # through every helm release that uses local.cg_repo_path / local.cg_repo
  # — no explicit `depends_on` needed on the helm releases.
  cg_repo_path = "${aws_ecr_pull_through_cache_rule.chainguard.ecr_repository_prefix}/${var.chainguard_org}"
  cg_repo      = "${local.ecr_registry}/${local.cg_repo_path}"
}

resource "aws_secretsmanager_secret" "chainguard_pull_creds" {
  name        = "ecr-pullthroughcache/${local.cluster_name}-chainguard"
  description = "Chainguard pull-token credentials for ECR pull-through cache (cluster ${local.cluster_name})."

  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "chainguard_pull_creds" {
  secret_id = aws_secretsmanager_secret.chainguard_pull_creds.id
  secret_string = jsonencode({
    username    = var.chainguard_pull_username
    accessToken = var.chainguard_pull_token
  })
}

resource "aws_ecr_pull_through_cache_rule" "chainguard" {
  ecr_repository_prefix = local.ecr_prefix
  upstream_registry_url = "cgr.dev"
  credential_arn        = aws_secretsmanager_secret_version.chainguard_pull_creds.arn
}

resource "aws_iam_policy" "ecr_pull_through_cache" {
  name        = "${local.cluster_name}-ecr-pull-through-cache"
  description = "Allow EKS nodes to trigger and tag pull-through-cache repositories under ${local.ecr_prefix}/."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:BatchImportUpstreamImage",
        "ecr:CreateRepository",
        "ecr:TagResource",
      ]
      Resource = [
        "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${local.ecr_prefix}/*",
      ]
    }]
  })

  tags = local.common_tags
}
