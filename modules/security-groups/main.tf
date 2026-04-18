# ── ALB Security Group ────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public-facing ALB: HTTP/HTTPS from internet"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from internet"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from internet"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nodes" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Forward traffic to EKS node ports"
}

# ── EKS Cluster (Control Plane) Security Group ────────────────────────────────
resource "aws_security_group" "eks_cluster" {
  name        = "${var.name}-eks-cluster"
  description = "EKS control plane: communication with nodes"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-eks-cluster" })
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "API server from nodes"
}

resource "aws_vpc_security_group_egress_rule" "cluster_to_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 1024
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Control plane to nodes (kubelet, logs)"
}

# ── EKS Node Security Group (additional SG attached to nodes) ─────────────────
resource "aws_security_group" "eks_nodes" {
  name        = "${var.name}-eks-nodes"
  description = "EKS worker nodes: ingress from ALB and control plane, egress to internet"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-eks-nodes" })
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_alb" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Traffic from ALB"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "-1"
  description                  = "Node-to-node communication"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_cluster" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.eks_cluster.id
  from_port                    = 1024
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Control plane to kubelet and NodePort services"
}

# Explicit egress rules for known external dependencies
resource "aws_vpc_security_group_egress_rule" "nodes_https_out" {
  security_group_id = aws_security_group.eks_nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS out — ECR, S3, AWS APIs, LaunchDarkly SaaS"
}

resource "aws_vpc_security_group_egress_rule" "nodes_http_out" {
  security_group_id = aws_security_group.eks_nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP out"
}

# Required for pods connecting to mycustom-api.com:4567
resource "aws_vpc_security_group_egress_rule" "nodes_custom_api" {
  security_group_id = aws_security_group.eks_nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 4567
  to_port           = 4567
  ip_protocol       = "tcp"
  description       = "mycustom-api.com on port 4567"
}

resource "aws_vpc_security_group_egress_rule" "nodes_dns_udp" {
  security_group_id = aws_security_group.eks_nodes.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  description       = "DNS (UDP) within VPC"
}

resource "aws_vpc_security_group_egress_rule" "nodes_dns_tcp" {
  security_group_id = aws_security_group.eks_nodes.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
  description       = "DNS (TCP) within VPC"
}

resource "aws_vpc_security_group_egress_rule" "nodes_intra_vpc" {
  security_group_id = aws_security_group.eks_nodes.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 0
  to_port           = 65535
  ip_protocol       = "-1"
  description       = "All traffic within VPC (RDS, internal services)"
}

# ── RDS Security Group ─────────────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS Aurora: inbound Postgres only from EKS nodes"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-rds" })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_nodes" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from EKS nodes only"
}

# ── VPC Endpoint Security Group ────────────────────────────────────────────────
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name}-vpce"
  description = "Interface VPC endpoints: HTTPS from VPC"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-vpce" })
}

resource "aws_vpc_security_group_ingress_rule" "vpce_https" {
  security_group_id = aws_security_group.vpc_endpoints.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from VPC to interface endpoints"
}
