output "grafana_service_name" {
  description = "Name of the Grafana service"
  value       = "${helm_release.prometheus.name}-grafana"
}

output "prometheus_service_name" {
  description = "Name of the Prometheus service"
  value       = "${helm_release.prometheus.name}-kube-prometheus-prometheus"
}

output "monitoring_namespace" {
  description = "Namespace where monitoring components are deployed"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}