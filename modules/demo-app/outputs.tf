output "namespace" {
  value = kubernetes_namespace.this.metadata[0].name
}

output "service_account_name" {
  value = kubernetes_service_account.this.metadata[0].name
}

output "service_name" {
  value = kubernetes_service.this.metadata[0].name
}

output "kubectl_port_forward" {
  value       = "kubectl port-forward -n ${kubernetes_namespace.this.metadata[0].name} svc/demo-app 8080:80"
  description = "Run this to test the demo app locally"
}
