locals {
  cg_charts = "oci://cgr.dev/${var.chainguard_org}/charts"

  # In real usage, you would want to use digests here (i.e 1.21.1@sha256:...).
  # But we can't know what the digests will be in your organization, so they're
  # unpinned here.
  cg_chart_versions = {
    aws-vpc-cni                  = "1.21.1"
    kube-proxy                   = "0.0.9"
    coredns                      = "1.46.0"
    aws-ebs-csi-driver           = "2.62.0"
    cert-manager                 = "v1.21.0"
    aws-load-balancer-controller = "3.4.2"
    external-dns                 = "1.21.1"
    metrics-server               = "3.13.1"
    cluster-autoscaler           = "9.58.0"
    kube-state-metrics           = "7.5.2"
  }
}

resource "helm_release" "vpc_cni" {
  name      = "aws-vpc-cni"
  chart     = "${local.cg_charts}/aws-vpc-cni"
  version   = local.cg_chart_versions["aws-vpc-cni"]
  namespace = "kube-system"

  # Generous timeout for cold-node IPAM init + DaemonSet rollout.
  timeout = 900

  values = [yamlencode({
    image = {
      repository = "${local.cg_repo}/amazon-k8s-cni"
    }
    init = {
      image = {
        repository = "${local.cg_repo}/amazon-k8s-cni-init"
      }
    }
    nodeAgent = {
      image = {
        repository = "${local.cg_repo}/aws-network-policy-agent"
      }
    }

    serviceAccount = {
      create = true
      name   = "aws-node"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.vpc_cni_irsa.iam_role_arn
      }
    }
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
    }
  })]

  # NB: don't add `depends_on = [module.eks]` here — that makes the helm
  # release wait for the node group to go ACTIVE, which waits for nodes
  # to be Ready, which needs THIS DaemonSet to land.
}

resource "helm_release" "kube_proxy" {
  name      = "kube-proxy"
  chart     = "${local.cg_charts}/kube-proxy"
  version   = local.cg_chart_versions["kube-proxy"]
  namespace = "kube-system"

  values = [yamlencode({
    image = {
      repository = "${local.cg_repo}/kubernetes-kube-proxy"
    }

    apiServer = {
      endpoint = module.eks.cluster_endpoint
    }
  })]
}

resource "helm_release" "coredns" {
  name      = "coredns"
  chart     = "${local.cg_charts}/coredns"
  version   = local.cg_chart_versions["coredns"]
  namespace = "kube-system"

  values = [yamlencode({
    image = {
      repository = "${local.cg_repo}/coredns"
    }
    autoscaler = {
      image = {
        repository = "${local.cg_repo}/cluster-proportional-autoscaler"
      }
    }

    service = {
      name      = "kube-dns"
      clusterIP = cidrhost(module.eks.cluster_service_cidr, 10)
    }
    replicaCount = 2
  })]

  depends_on = [helm_release.vpc_cni]
}

resource "helm_release" "aws_ebs_csi_driver" {
  name      = "aws-ebs-csi-driver"
  chart     = "${local.cg_charts}/aws-ebs-csi-driver"
  version   = local.cg_chart_versions["aws-ebs-csi-driver"]
  namespace = "kube-system"

  values = [yamlencode({
    image = {
      repository = "${local.cg_repo}/aws-ebs-csi-driver"
    }
    sidecars = {
      attacher            = { image = { repository = "${local.cg_repo}/kubernetes-csi-external-attacher" } }
      livenessProbe       = { image = { repository = "${local.cg_repo}/kubernetes-csi-livenessprobe" } }
      nodeDriverRegistrar = { image = { repository = "${local.cg_repo}/kubernetes-csi-node-driver-registrar" } }
      provisioner         = { image = { repository = "${local.cg_repo}/kubernetes-csi-external-provisioner" } }
      resizer             = { image = { repository = "${local.cg_repo}/kubernetes-csi-external-resizer" } }
      snapshotter         = { image = { repository = "${local.cg_repo}/kubernetes-csi-external-snapshotter" } }
      volumemodifier      = { image = { repository = "${local.cg_repo}/aws-volume-modifier-for-k8s" } }
    }

    controller = {
      serviceAccount = {
        create = true
        name   = "ebs-csi-controller-sa"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.ebs_csi_irsa.iam_role_arn
        }
      }
    }
  })]

  depends_on = [helm_release.vpc_cni]
}

resource "helm_release" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name             = "cert-manager"
  chart            = "${local.cg_charts}/cert-manager"
  version          = local.cg_chart_versions["cert-manager"]
  namespace        = "cert-manager"
  create_namespace = true

  values = [yamlencode({
    image = {
      registry   = local.ecr_registry
      repository = "${local.cg_repo_path}/cert-manager-controller"
    }
    webhook = {
      image = {
        registry   = local.ecr_registry
        repository = "${local.cg_repo_path}/cert-manager-webhook"
      }
    }
    cainjector = {
      image = {
        registry   = local.ecr_registry
        repository = "${local.cg_repo_path}/cert-manager-cainjector"
      }
    }
    acmesolver = {
      image = {
        registry   = local.ecr_registry
        repository = "${local.cg_repo_path}/cert-manager-acmesolver"
      }
    }
    startupapicheck = {
      image = {
        registry   = local.ecr_registry
        repository = "${local.cg_repo_path}/cert-manager-startupapicheck"
      }
    }

    crds = { enabled = true }
  })]

  depends_on = [helm_release.coredns]
}

resource "helm_release" "aws_load_balancer_controller" {
  count = var.enable_aws_load_balancer_controller ? 1 : 0

  name      = "aws-load-balancer-controller"
  chart     = "${local.cg_charts}/aws-load-balancer-controller"
  version   = local.cg_chart_versions["aws-load-balancer-controller"]
  namespace = "kube-system"

  values = [yamlencode({
    image = {
      repository = "${local.cg_repo}/aws-load-balancer-controller"
    }

    clusterName = local.cluster_name
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.aws_load_balancer_controller_irsa[0].iam_role_arn
      }
    }
  })]

  depends_on = [helm_release.coredns]
}

resource "helm_release" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name      = "external-dns"
  chart     = "${local.cg_charts}/external-dns"
  version   = local.cg_chart_versions["external-dns"]
  namespace = "kube-system"

  values = [yamlencode({
    image = {
      repository = "${local.cg_repo}/external-dns"
    }
    provider = {
      webhook = {
        image = {
          repository = "${local.cg_repo}/external-dns"
        }
      }
    }

    serviceAccount = {
      create = true
      name   = "external-dns"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.external_dns_irsa[0].iam_role_arn
      }
    }
    domainFilters = var.external_dns_domain_filters
    txtOwnerId    = local.cluster_name
  })]

  depends_on = [helm_release.coredns]
}

resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  name      = "metrics-server"
  chart     = "${local.cg_charts}/metrics-server"
  version   = local.cg_chart_versions["metrics-server"]
  namespace = "kube-system"

  values = [yamlencode({
    image = {
      repository = "${local.cg_repo}/metrics-server"
    }
    addonResizer = {
      image = {
        repository = "${local.cg_repo}/kubernetes-autoscaler-addon-resizer"
      }
    }
  })]

  depends_on = [helm_release.coredns]
}

resource "helm_release" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  name      = "cluster-autoscaler"
  chart     = "${local.cg_charts}/cluster-autoscaler"
  version   = local.cg_chart_versions["cluster-autoscaler"]
  namespace = "kube-system"

  values = [yamlencode({
    image = {
      repository = "${local.cg_repo}/cluster-autoscaler"
    }

    autoDiscovery = {
      clusterName = local.cluster_name
    }
    awsRegion = var.region
    rbac = {
      serviceAccount = {
        create = true
        name   = "cluster-autoscaler"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.cluster_autoscaler_irsa[0].iam_role_arn
        }
      }
    }
  })]

  depends_on = [helm_release.coredns]
}

resource "helm_release" "kube_state_metrics" {
  count = var.enable_kube_state_metrics ? 1 : 0

  name      = "kube-state-metrics"
  chart     = "${local.cg_charts}/kube-state-metrics"
  version   = local.cg_chart_versions["kube-state-metrics"]
  namespace = "kube-system"

  values = [yamlencode({
    image = {
      registry   = local.ecr_registry
      repository = "${local.cg_repo_path}/kube-state-metrics"
    }
    kubeRBACProxy = {
      image = {
        registry   = local.ecr_registry
        repository = "${local.cg_repo_path}/kube-rbac-proxy"
      }
    }
  })]

  depends_on = [helm_release.coredns]
}
