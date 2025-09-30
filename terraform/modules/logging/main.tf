resource "kubernetes_namespace" "logging" {
  metadata {
    name = "logging"
    labels = {
      name = "logging"
    }
  }
}

resource "helm_release" "elasticsearch" {
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = "8.5.1"

  values = [
    yamlencode({
      replicas = 3
      minimumMasterNodes = 2

      esConfig = {
        "elasticsearch.yml" = <<-EOT
          cluster.name: "docker-cluster"
          network.host: 0.0.0.0
          discovery.type: zen
          discovery.zen.minimum_master_nodes: 2
          discovery.zen.ping.unicast.hosts: "elasticsearch-master-headless"
        EOT
      }

      resources = {
        requests = {
          cpu    = "1000m"
          memory = "2Gi"
        }
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
      }

      volumeClaimTemplate = {
        storageClassName = "gp2"
        accessModes      = ["ReadWriteOnce"]
        resources = {
          requests = {
            storage = "100Gi"
          }
        }
      }

      nodeSelector = {
        role = "general"
      }
    })
  ]

  depends_on = [kubernetes_namespace.logging]
}

resource "helm_release" "kibana" {
  name       = "kibana"
  repository = "https://helm.elastic.co"
  chart      = "kibana"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = "8.5.1"

  values = [
    yamlencode({
      elasticsearchHosts = "http://elasticsearch-master:9200"

      resources = {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
      }

      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
        }
      }

      nodeSelector = {
        role = "general"
      }
    })
  ]

  depends_on = [helm_release.elasticsearch]
}

resource "helm_release" "logstash" {
  name       = "logstash"
  repository = "https://helm.elastic.co"
  chart      = "logstash"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = "8.5.1"

  values = [
    yamlencode({
      replicas = 2

      logstashConfig = {
        "logstash.yml" = <<-EOT
          http.host: "0.0.0.0"
          path.config: /usr/share/logstash/pipeline
        EOT
      }

      logstashPipeline = {
        "logstash.conf" = <<-EOT
          input {
            beats {
              port => 5044
            }
          }
          filter {
            if [kubernetes] {
              mutate {
                add_field => { "cluster_name" => "${var.cluster_name}" }
              }
            }
          }
          output {
            elasticsearch {
              hosts => ["http://elasticsearch-master:9200"]
              index => "kubernetes-logs-%%{+YYYY.MM.dd}"
            }
          }
        EOT
      }

      resources = {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
      }

      nodeSelector = {
        role = "general"
      }
    })
  ]

  depends_on = [helm_release.elasticsearch]
}

resource "helm_release" "filebeat" {
  name       = "filebeat"
  repository = "https://helm.elastic.co"
  chart      = "filebeat"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = "8.5.1"

  values = [
    yamlencode({
      daemonset = {
        enabled = true
      }

      filebeatConfig = {
        "filebeat.yml" = <<-EOT
          filebeat.inputs:
          - type: container
            paths:
              - /var/log/containers/*.log
            processors:
            - add_kubernetes_metadata:
                host: $${NODE_NAME}
                matchers:
                - logs_path:
                    logs_path: "/var/log/containers/"

          output.logstash:
            hosts: ["logstash-logstash:5044"]

          processors:
            - add_host_metadata:
                when.not.contains.tags: forwarded
        EOT
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "100Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "200Mi"
        }
      }

      extraVolumeMounts = [
        {
          name      = "varlibdockercontainers"
          mountPath = "/var/lib/docker/containers"
          readOnly  = true
        }
      ]

      extraVolumes = [
        {
          name = "varlibdockercontainers"
          hostPath = {
            path = "/var/lib/docker/containers"
          }
        }
      ]
    })
  ]

  depends_on = [helm_release.logstash]
}