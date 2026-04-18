data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than ${var.lifecycle_untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.lifecycle_untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the ${var.lifecycle_tagged_keep_count} most recent tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = var.lifecycle_tagged_keep_count
        }
        action = { type = "expire" }
      }
    ]
  })
}

locals {
  all_pull_principals = concat(
    ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
    var.cross_account_pull_arns
  )
}

# Only created when there are cross-account consumers; same-account pull is
# handled automatically by the node role's AmazonEC2ContainerRegistryReadOnly.
resource "aws_ecr_repository_policy" "this" {
  count      = length(var.cross_account_pull_arns) > 0 ? 1 : 0
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCrossAccountPull"
        Effect    = "Allow"
        Principal = { AWS = local.all_pull_principals }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}
