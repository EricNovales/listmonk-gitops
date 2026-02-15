resource "helm_release" "kps" {
  name       = "kps"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "56.6.0"

  values = [
    file("${path.module}/../monitoring/kps/values.base.yaml"),
    file("${path.module}/../monitoring/kps/values.grafana.yaml"),
    file("${path.module}/../monitoring/kps/values.ingress.yaml"),
    file("${path.module}/../monitoring/kps/values.datasources.yaml"),
    file("${path.module}/../monitoring/kps/values.dashboards.yaml"),
    file("${path.module}/../monitoring/kps/values.alerting.yaml"),
  ]

  # Recomendado para que helm falle "bien"
  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 900

  depends_on = [kubernetes_namespace_v1.monitoring]
}
