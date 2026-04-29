# ── IAM Role — Pod Identity trust policy ──────────────────────────────────────
# Pod Identity uses pods.eks.amazonaws.com as the service principal.
# Unlike IRSA, no service account annotation is required — the association
# resource below is the only binding between the K8s SA and this IAM role.
resource "aws_iam_role" "app" {
  name = "${var.name}-pod-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "pods.eks.amazonaws.com" }
        Action    = ["sts:AssumeRole", "sts:TagSession"]
      }
    ]
  })

  tags = var.tags
}

# ── S3 full access (scoped to the environment's buckets) ──────────────────────
resource "aws_iam_policy" "s3_full" {
  name        = "${var.name}-pod-s3-full"
  description = "Full S3 access to environment buckets for EKS pods"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3BucketAccess"
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = flatten([
          for arn in var.s3_bucket_arns : [arn, "${arn}/*"]
        ])
      },
      {
        Sid      = "S3ListAllBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# ── AWS Translate full access ──────────────────────────────────────────────────
resource "aws_iam_policy" "translate_full" {
  name        = "${var.name}-pod-translate-full"
  description = "Full AWS Translate access for EKS pods"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TranslateFullAccess"
        Effect   = "Allow"
        Action   = ["translate:*", "comprehend:DetectDominantLanguage", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics"]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "s3_full" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.s3_full.arn
}

resource "aws_iam_role_policy_attachment" "translate_full" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.translate_full.arn
}

# ── Pod Identity Association ───────────────────────────────────────────────────
# Links the K8s service account (namespace/name) to the IAM role above.
# The pod-identity-agent DaemonSet intercepts credential requests from pods
# using this SA and vends short-lived AWS credentials automatically.
resource "aws_eks_pod_identity_association" "app" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.app.arn
  tags            = var.tags
}
