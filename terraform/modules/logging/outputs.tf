output "elasticsearch_service_name" {
  description = "Name of the Elasticsearch service"
  value       = "${helm_release.elasticsearch.name}-master"
}

output "kibana_service_name" {
  description = "Name of the Kibana service"
  value       = "${helm_release.kibana.name}-kibana"
}

output "logstash_service_name" {
  description = "Name of the Logstash service"
  value       = "${helm_release.logstash.name}-logstash"
}

output "logging_namespace" {
  description = "Namespace where logging components are deployed"
  value       = kubernetes_namespace.logging.metadata[0].name
}