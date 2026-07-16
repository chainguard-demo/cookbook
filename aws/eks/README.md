# AWS EKS

This is an example of deploying an AWS EKS cluster with Chainguard images.

It uses Chainguard Helm Charts to deploy common addons like `kube-proxy` and
`coredns`.

## What's Deployed

| Component                                 | Source                            | Chart                          | Pinned version |
| ----------------------------------------- | --------------------------------- | ------------------------------ | -------------- |
| VPC + subnets                             | `terraform-aws-modules/vpc/aws`   | —                              | —              |
| EKS control plane + managed node group    | `terraform-aws-modules/eks/aws`   | —                              | —              |
| ECR pull-through cache rule for `cgr.dev` | `aws_ecr_pull_through_cache_rule` | —                              | —              |
| VPC CNI (`aws-node`)                      | Helm                              | `aws-vpc-cni`                  | `1.21.1`       |
| kube-proxy                                | Helm                              | `kube-proxy`                   | `0.0.9`        |
| CoreDNS                                   | Helm                              | `coredns`                      | `1.45.2`       |
| AWS EBS CSI Driver                        | Helm                              | `aws-ebs-csi-driver`           | `2.59.0`       |
| cert-manager                              | Helm                              | `cert-manager`                 | `v1.20.2`      |
| AWS Load Balancer Controller              | Helm                              | `aws-load-balancer-controller` | `3.3.0`        |
| external-dns *(optional)*                 | Helm                              | `external-dns`                 | `1.21.1`       |
| metrics-server                            | Helm                              | `metrics-server`               | `3.13.0`       |
| cluster-autoscaler                        | Helm                              | `cluster-autoscaler`           | `9.57.0`       |
| kube-state-metrics *(optional)*           | Helm                              | `kube-state-metrics`           | `7.3.0`        |

## Usage

```hcl
module "eks" {
  source = "github.com/chainguard_demo/cookbook//aws/eks"

  region             = "us-west-2"
  cluster_name       = "my-cluster"
  kubernetes_version = "1.35"

  chainguard_org           = "my-org"
  chainguard_pull_username = "..."   # pass via TF_VAR_chainguard_pull_username
  chainguard_pull_token    = "..."   # pass via TF_VAR_chainguard_pull_token
}
```

```sh
# Create a pull token
chainctl auth pull-token create \
  --parent my-org \
  --ttl 8760h \
  --save \
  --output json \
  | tee /tmp/pull-token.json

# Export the token credentials
export TF_VAR_chainguard_pull_username=$(jq -r '.username // .identity_id' /tmp/pull-token.json)
export TF_VAR_chainguard_pull_token=$(jq -r '.password // .token' /tmp/pull-token.json)

# Apply the terraform
terraform init
terraform apply

# Update your kube config
aws eks update-kubeconfig --region us-west-2 --name my-cluster
```

## Variables

See [`variables.tf`](./variables.tf). 

Required:

- `cluster_name`
- `chainguard_org`
- `chainguard_pull_username`
- `chainguard_pull_token`

## Outputs

See [`outputs.tf`](./outputs.tf).
