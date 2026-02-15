resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.44.0"

  values = [
    file("${path.module}/../monitoring/values-loki.yaml")
  ]

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 900

  depends_on = [kubernetes_namespace_v1.monitoring]
}

