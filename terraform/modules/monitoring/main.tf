resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      name = "monitoring"
    }
  }
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "51.2.0"

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention = "30d"
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp2"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "50Gi"
                  }
                }
              }
            }
          }
          nodeSelector = {
            role = "monitoring"
          }
          tolerations = [{
            key      = "monitoring"
            operator = "Equal"
            value    = "true"
            effect   = "NoSchedule"
          }]
        }
      }
      grafana = {
        adminPassword = "admin123"
        persistence = {
          enabled = true
          size    = "10Gi"
        }
        nodeSelector = {
          role = "monitoring"
        }
        tolerations = [{
          key      = "monitoring"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }]
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
          }
        }
      }
      alertmanager = {
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp2"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
          nodeSelector = {
            role = "monitoring"
          }
          tolerations = [{
            key      = "monitoring"
            operator = "Equal"
            value    = "true"
            effect   = "NoSchedule"
          }]
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

resource "helm_release" "prometheus_node_exporter" {
  name       = "prometheus-node-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-node-exporter"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "4.21.0"

  depends_on = [kubernetes_namespace.monitoring]
}

resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "custom-dashboards"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "kubernetes-cluster-dashboard.json" = file("${path.module}/dashboards/kubernetes-cluster.json")
    "istio-service-dashboard.json"      = file("${path.module}/dashboards/istio-service.json")
  }

  depends_on = [helm_release.prometheus]
}