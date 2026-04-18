output "protection_group_id" {
  value = aws_shield_protection_group.all.id
}

output "cloudfront_protection_id" {
  value = aws_shield_protection.cloudfront.id
}

output "route53_protection_id" {
  value = aws_shield_protection.route53.id
}

output "nat_eip_protection_ids" {
  value = aws_shield_protection.nat_eip[*].id
}
