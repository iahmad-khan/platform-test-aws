output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "eks_cluster_sg_id" {
  value = aws_security_group.eks_cluster.id
}

output "eks_node_sg_id" {
  value = aws_security_group.eks_nodes.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}

output "vpc_endpoint_sg_id" {
  value = aws_security_group.vpc_endpoints.id
}
