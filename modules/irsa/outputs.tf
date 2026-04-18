output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}

output "external_dns_role_arn" {
  value = aws_iam_role.external_dns.arn
}
