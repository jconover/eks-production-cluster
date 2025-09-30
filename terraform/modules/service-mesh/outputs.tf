output "istio_namespace" {
  description = "Namespace where Istio system components are deployed"
  value       = kubernetes_namespace.istio_system.metadata[0].name
}

output "istio_ingress_namespace" {
  description = "Namespace where Istio ingress gateway is deployed"
  value       = kubernetes_namespace.istio_ingress.metadata[0].name
}

output "kiali_service_name" {
  description = "Name of the Kiali service"
  value       = "kiali"
}

output "jaeger_service_name" {
  description = "Name of the Jaeger query service"
  value       = "${helm_release.jaeger.name}-query"
}

output "istio_gateway_name" {
  description = "Name of the main Istio gateway"
  value       = "main-gateway"
}