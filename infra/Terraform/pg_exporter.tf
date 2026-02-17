resource "helm_release" "pg_exporter" {
  name       = "pg-exporter"
  namespace  = kubernetes_namespace_v1.listmonk.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-postgres-exporter"
  version    = "7.5.0"

  values = [
    file("${path.module}/../monitoring/values.postgres-exporter.yaml")
  ]

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  depends_on = [kubernetes_namespace_v1.listmonk]
}
