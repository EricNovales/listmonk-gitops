resource "kubernetes_manifest" "listmonk_postgres_sealedsecret" {
  manifest = yamldecode(file("${path.module}/secrets/postgres-sealedsecret.yaml"))

  depends_on = [
    kubernetes_namespace_v1.listmonk
  ]
}
