############################################
# default-deny
############################################
resource "kubernetes_network_policy_v1" "listmonk_default_deny" {
  metadata {
    name      = "default-deny"
    namespace = kubernetes_namespace_v1.listmonk.metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]
  }
 depends_on = [kubernetes_namespace_v1.listmonk]
}

############################################
# allow-dns-egress
############################################
resource "kubernetes_network_policy_v1" "listmonk_allow_dns_egress" {
  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace_v1.listmonk.metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }

      ports {
        protocol = "UDP"
        port     = 53
      }
      ports {
        protocol = "TCP"
        port     = 53
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.listmonk_default_deny]
}

############################################
# allow-egress-analysis-to-listmonk-and-dns
# (en tu YAML solo permite HTTP 9000 hacia pods app=listmonk)
############################################
resource "kubernetes_network_policy_v1" "listmonk_allow_egress_analysis_to_listmonk" {
  metadata {
    name      = "allow-egress-analysis-to-listmonk-and-dns"
    namespace = kubernetes_namespace_v1.listmonk.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        role = "analysis"
      }
    }

    policy_types = ["Egress"]

    egress {
      to {
        pod_selector {
          match_labels = {
            app = "listmonk"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = 9000
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.listmonk_default_deny]
}

############################################
# allow-egress-from-listmonk
# - listmonk -> postgres:5432 (same namespace)
# - listmonk -> mail/mailpit:1025
############################################
resource "kubernetes_network_policy_v1" "listmonk_allow_egress_from_listmonk" {
  metadata {
    name      = "allow-egress-from-listmonk"
    namespace = kubernetes_namespace_v1.listmonk.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "listmonk"
      }
    }

    policy_types = ["Egress"]

    # -> Postgres (mismo namespace)
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "postgres"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = 5432
      }
    }

    # -> Mailpit SMTP (namespace mail)
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "mail"
          }
        }
        pod_selector {
          match_labels = {
            app = "mailpit"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = 1025
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.listmonk_default_deny]
}

############################################
# allow-ingress-to-listmonk-from-analysis
############################################
resource "kubernetes_network_policy_v1" "listmonk_allow_ingress_to_listmonk_from_analysis" {
  metadata {
    name      = "allow-ingress-to-listmonk-from-analysis"
    namespace = kubernetes_namespace_v1.listmonk.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "listmonk"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            role = "analysis"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = 9000
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.listmonk_default_deny]
}

############################################
# allow-ingress-nginx-to-listmonk
############################################
resource "kubernetes_network_policy_v1" "listmonk_allow_ingress_nginx_to_listmonk" {
  metadata {
    name      = "allow-ingress-nginx-to-listmonk"
    namespace = kubernetes_namespace_v1.listmonk.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "listmonk"
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
        port     = 9000
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.listmonk_default_deny]
}

############################################
# allow-listmonk-to-postgres
# (ingress policy en los pods app=postgres para aceptar de app=listmonk)
############################################
resource "kubernetes_network_policy_v1" "listmonk_allow_listmonk_to_postgres" {
  metadata {
    name      = "allow-listmonk-to-postgres"
    namespace = kubernetes_namespace_v1.listmonk.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "postgres"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "listmonk"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = 5432
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.listmonk_default_deny]
}

