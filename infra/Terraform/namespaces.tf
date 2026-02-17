############################################
# Namespace monitoring
############################################
resource "kubernetes_namespace_v1" "monitoring" {
  metadata { name = "monitoring" }
}
############################################
# Namespace listmonk app
############################################
resource "kubernetes_namespace_v1" "listmonk" {
  metadata { name = "listmonk" }
}
############################################
# Namespace mail
############################################
resource "kubernetes_namespace_v1" "mail" {
  metadata { name = "mail" }
}
############################################
# Namespace argocd
############################################
resource "kubernetes_namespace_v1" "argocd" {
  metadata { name = "argocd" }
}
############################################
# Namespace argo-rollouts
############################################
resource "kubernetes_namespace_v1" "argo-rollouts" {
  metadata { name = "argo-rollouts" }
}
