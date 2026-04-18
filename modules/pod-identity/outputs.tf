output "role_arn" {
  value       = aws_iam_role.app.arn
  description = "IAM role ARN bound to the pod service account via Pod Identity"
}

output "role_name" {
  value = aws_iam_role.app.name
}

output "association_id" {
  value = aws_eks_pod_identity_association.app.association_id
}
