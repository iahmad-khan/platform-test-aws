variable "name" {
  type        = string
  description = "EKS cluster name"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.31"
  description = "Kubernetes version for the EKS cluster"
}

variable "cluster_role_arn" {
  type        = string
  description = "IAM role ARN for EKS control plane"
}

variable "node_role_arn" {
  type        = string
  description = "IAM role ARN for Auto Mode node provisioner"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs where nodes and control plane ENIs are placed"
}

variable "cluster_sg_id" {
  type        = string
  description = "Additional cluster security group ID"
}

variable "node_sg_id" {
  type        = string
  description = "Additional node security group ID"
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Enable public API endpoint"
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API endpoint"
}

variable "alb_controller_role_arn" {
  type        = string
  description = "IRSA role ARN for AWS Load Balancer Controller"
}

variable "node_tenant_label" {
  type        = string
  default     = "amd-hosts"
  description = "Value for the tenantname node label applied via NodePool"
}

variable "enable_kube_prometheus" {
  type        = bool
  default     = true
  description = "Install kube-prometheus-stack via Helm"
}

variable "enable_argocd" {
  type        = bool
  default     = true
  description = "Install ArgoCD via Helm"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to all resources"
}
