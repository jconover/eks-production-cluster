resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = "istio-system"
    labels = {
      name                = "istio-system"
      "istio-injection"   = "disabled"
    }
  }
}

resource "kubernetes_namespace" "istio_ingress" {
  metadata {
    name = "istio-ingress"
    labels = {
      name              = "istio-ingress"
      "istio-injection" = "enabled"
    }
  }
}

resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  version    = "1.19.3"

  depends_on = [kubernetes_namespace.istio_system]
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  version    = "1.19.3"

  values = [
    yamlencode({
      pilot = {
        nodeSelector = {
          role = "general"
        }
        resources = {
          requests = {
            cpu    = "500m"
            memory = "2048Mi"
          }
        }
      }

      global = {
        meshID      = "mesh1"
        multiCluster = {
          clusterName = var.cluster_name
        }
        network = "network1"
      }
    })
  ]

  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_ingress" {
  name       = "istio-ingress"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = kubernetes_namespace.istio_ingress.metadata[0].name
  version    = "1.19.3"

  values = [
    yamlencode({
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
          "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
        }
      }

      nodeSelector = {
        role = "general"
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "2000m"
          memory = "1024Mi"
        }
      }
    })
  ]

  depends_on = [
    helm_release.istiod,
    kubernetes_namespace.istio_ingress
  ]
}

resource "kubectl_manifest" "istio_gateway" {
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: main-gateway
  namespace: ${kubernetes_namespace.istio_ingress.metadata[0].name}
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: main-gateway-cert
    hosts:
    - "*"
YAML

  depends_on = [helm_release.istio_ingress]
}

resource "kubectl_manifest" "kiali" {
  yaml_body = <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kiali
  namespace: ${kubernetes_namespace.istio_system.metadata[0].name}
  labels:
    app: kiali
    version: v1.73.0
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kiali
  namespace: ${kubernetes_namespace.istio_system.metadata[0].name}
  labels:
    app: kiali
    version: v1.73.0
data:
  config.yaml: |
    auth:
      strategy: anonymous
    deployment:
      accessible_namespaces:
      - "**"
    external_services:
      prometheus:
        url: "http://prometheus-kube-prometheus-prometheus.monitoring:9090"
      grafana:
        in_cluster_url: "http://prometheus-grafana.monitoring:80"
        url: "http://prometheus-grafana.monitoring:80"
      tracing:
        in_cluster_url: "http://jaeger-query.istio-system:16686"
        url: "http://jaeger-query.istio-system:16686"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kiali
  namespace: ${kubernetes_namespace.istio_system.metadata[0].name}
  labels:
    app: kiali
    version: v1.73.0
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kiali
      version: v1.73.0
  template:
    metadata:
      labels:
        app: kiali
        version: v1.73.0
    spec:
      serviceAccountName: kiali
      containers:
      - image: quay.io/kiali/kiali:v1.73.0
        imagePullPolicy: Always
        name: kiali
        command:
        - "/opt/kiali/kiali"
        - "-config"
        - "/kiali-configuration/config.yaml"
        ports:
        - containerPort: 20001
          protocol: TCP
        readinessProbe:
          httpGet:
            path: /kiali/healthz
            port: 20001
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 30
        livenessProbe:
          httpGet:
            path: /kiali/healthz
            port: 20001
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 30
        env:
        - name: ACTIVE_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: LOG_LEVEL
          value: "info"
        - name: LOG_FORMAT
          value: "text"
        - name: LOG_TIME_FIELD_FORMAT
          value: "2006-01-02T15:04:05Z07:00"
        - name: LOG_SAMPLER_RATE
          value: "1"
        volumeMounts:
        - name: kiali-configuration
          mountPath: "/kiali-configuration"
        - name: kiali-cert
          mountPath: "/kiali-cert"
        - name: kiali-secret
          mountPath: "/kiali-secret"
      volumes:
      - name: kiali-configuration
        configMap:
          name: kiali
      - name: kiali-cert
        secret:
          secretName: istio.kiali-service-account
          optional: true
      - name: kiali-secret
        secret:
          secretName: kiali
          optional: true
---
apiVersion: v1
kind: Service
metadata:
  name: kiali
  namespace: ${kubernetes_namespace.istio_system.metadata[0].name}
  labels:
    app: kiali
    version: v1.73.0
spec:
  type: LoadBalancer
  ports:
  - name: http-kiali
    port: 20001
    protocol: TCP
    targetPort: 20001
  selector:
    app: kiali
YAML

  depends_on = [helm_release.istiod]
}

resource "helm_release" "jaeger" {
  name       = "jaeger"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger"
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  version    = "0.71.11"

  values = [
    yamlencode({
      provisionDataStore = {
        cassandra = false
        elasticsearch = true
      }

      storage = {
        type = "elasticsearch"
        elasticsearch = {
          scheme = "http"
          host   = "elasticsearch-master.logging"
          port   = 9200
          user   = ""
          password = ""
        }
      }

      agent = {
        enabled = false
      }

      collector = {
        service = {
          type = "ClusterIP"
        }
        nodeSelector = {
          role = "general"
        }
      }

      query = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
          }
        }
        nodeSelector = {
          role = "general"
        }
      }
    })
  ]

  depends_on = [helm_release.istiod]
}