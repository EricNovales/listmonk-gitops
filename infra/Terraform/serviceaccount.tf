############################################
# ServiceAccount listmonk app
############################################
resource "kubernetes_service_account_v1" "listmonk" {
  metadata {
    name      = "listmonk"
    namespace = kubernetes_namespace_v1.listmonk.metadata[0].name

    labels = {
      app = "listmonk"
    }
  }
}

############################################
# ServiceAccount postgres
############################################
resource "kubernetes_service_account_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace_v1.listmonk.metadata[0].name

    labels = {
      app = "postgres"
    }
  }
}

############################################
# ServiceAccount mailpit
############################################
resource "kubernetes_service_account_v1" "mailpit" {
  metadata {
    name      = "mailpit"
    namespace = kubernetes_namespace_v1.mail.metadata[0].name

    labels = {
      app = "mailpit"
    }
  }
}

