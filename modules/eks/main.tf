data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── EKS Cluster (Auto Mode) ────────────────────────────────────────────────────
resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = [var.cluster_sg_id]
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  compute_config {
    enabled       = true
    node_pools    = ["general-purpose"]
    node_role_arn = var.node_role_arn
  }

  kubernetes_network_config {
    elastic_load_balancing { enabled = true }
  }

  storage_config {
    block_storage { enabled = true }
  }

  bootstrap_self_managed_addons = false
  tags                          = var.tags
}

# ── EKS Pod Identity Agent ─────────────────────────────────────────────────────
resource "aws_eks_addon" "pod_identity" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
  depends_on                  = [aws_eks_cluster.this]
}

# ── Pod Identity — helper local ────────────────────────────────────────────────
locals {
  pod_identity_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# ── IAM: AWS Load Balancer Controller ─────────────────────────────────────────
resource "aws_iam_role" "lbc" {
  name               = "${var.name}-lbc"
  assume_role_policy = local.pod_identity_trust
  tags               = var.tags
}

resource "aws_iam_policy" "lbc" {
  name   = "${var.name}-lbc-policy"
  policy = file("${path.module}/policies/alb_controller.json")
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn
  tags            = var.tags
  depends_on      = [aws_eks_addon.pod_identity]
}

# ── IAM: EBS CSI Driver ────────────────────────────────────────────────────────
resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi"
  assume_role_policy = local.pod_identity_trust
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
  tags            = var.tags
  depends_on      = [aws_eks_addon.pod_identity]
}

# ── IAM: External DNS ──────────────────────────────────────────────────────────
resource "aws_iam_role" "external_dns" {
  name               = "${var.name}-external-dns"
  assume_role_policy = local.pod_identity_trust
  tags               = var.tags
}

resource "aws_iam_policy" "external_dns" {
  name = "${var.name}-external-dns-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = [var.route53_zone_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
        Resource = ["*"]
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
  tags            = var.tags
  depends_on      = [aws_eks_addon.pod_identity]
}

# ── Node pool with custom labels ───────────────────────────────────────────────
resource "kubernetes_manifest" "node_pool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "${var.name}-labeled" }
    spec = {
      template = {
        metadata = { labels = { tenantname = var.node_tenant_label } }
        spec = {
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "default"
          }
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            { key = "kubernetes.io/arch",          operator = "In", values = ["amd64"] }
          ]
        }
      }
      disruption = { consolidationPolicy = "WhenEmptyOrUnderutilized", consolidateAfter = "1m" }
    }
  }
  depends_on = [aws_eks_cluster.this]
}

# ── Helm: AWS Load Balancer Controller ────────────────────────────────────────
# No IRSA annotation — Pod Identity association above provides credentials.
resource "helm_release" "aws_lbc" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "kube-system"
  create_namespace = false
  version          = "1.8.3"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.this.name
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "region"
    value = data.aws_region.current.name
  }

  depends_on = [aws_eks_addon.pod_identity, aws_eks_pod_identity_association.lbc]
}

# ── Helm: Metrics Server ───────────────────────────────────────────────────────
resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  namespace        = "kube-system"
  create_namespace = false
  version          = "3.12.1"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [aws_eks_cluster.this]
}

# ── Helm: kube-prometheus-stack ────────────────────────────────────────────────
resource "helm_release" "kube_prometheus" {
  count            = var.enable_kube_prometheus ? 1 : 0
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  version          = "61.3.2"

  set {
    name  = "grafana.adminPassword"
    value = "changeme-use-secret-manager"
  }
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "30d"
  }
  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "50Gi"
  }

  depends_on = [aws_eks_cluster.this]
}

# ── Helm: ArgoCD ───────────────────────────────────────────────────────────────
resource "helm_release" "argocd" {
  count            = var.enable_argocd ? 1 : 0
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.3.11"

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  depends_on = [aws_eks_cluster.this]
}
