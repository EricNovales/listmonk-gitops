resource "kubernetes_manifest" "aws-user_sealedsecret" {
  manifest = yamldecode(file("${path.module}/secrets/aws-user.sealedsecret.yaml"))

  depends_on = [
    kubernetes_namespace_v1.listmonk
  ]
}
