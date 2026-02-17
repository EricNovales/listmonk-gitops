resource "kubernetes_manifest" "monitoring_sealedsecret" {
  manifest = yamldecode(file("${path.module}/secrets/grafana-admin.sealedsecret.yaml"))

  depends_on = [
    kubernetes_namespace_v1.monitoring
  ]
}
