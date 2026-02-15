resource "helm_release" "promtail" {
  name       = "promtail"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.15.0"

  values = [
    file("${path.module}/../monitoring/values-promtail.yaml")
  ]

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 900

  depends_on = [kubernetes_namespace_v1.monitoring]
}
