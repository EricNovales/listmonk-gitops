############################################
#NP mail
############################################
# default-deny (Ingress + Egress)
############################################
resource "kubernetes_network_policy_v1" "mail_default_deny" {
  metadata {
    name      = "default-deny"
    namespace = "mail"
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]
  }
 depends_on = [kubernetes_network_policy_v1.listmonk_default_deny]
}

############################################
# allow-ui-from-ingress-nginx
############################################
resource "kubernetes_network_policy_v1" "mail_allow_ui_from_ingress_nginx" {
  metadata {
    name      = "allow-ui-from-ingress-nginx"
    namespace = "mail"
  }

  spec {
    pod_selector {
      match_labels = {
        app = "mailpit"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "ingress-nginx"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = 8025
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.mail_default_deny]
}

############################################
# allow-smtp-from-listmonk
############################################
resource "kubernetes_network_policy_v1" "mail_allow_smtp_from_listmonk" {
  metadata {
    name      = "allow-smtp-from-listmonk"
    namespace = "mail"
  }

  spec {
    pod_selector {
      match_labels = {
        app = "mailpit"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "listmonk"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = 1025
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.mail_default_deny]
}
