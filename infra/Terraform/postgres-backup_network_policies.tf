############################################
# allow-backup-egress-postgres-localstack (Egress)
############################################

resource "kubernetes_network_policy_v1" "allow_backup_egress_postgres_localstack" {
  metadata {
    name      = "allow-backup-egress-postgres-dns-localstack"
    namespace = "listmonk"
  }

  spec {
    pod_selector {
      match_labels = {
        app = "postgres-backup"
      }
    }

    policy_types = ["Egress"]

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

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "localstack"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = 4566
      }
    }
  }
	depends_on = [kubernetes_network_policy_v1.listmonk_default_deny]
}

############################################
# allow-backup-into-postgres (Ingress)
############################################

resource "kubernetes_network_policy_v1" "allow_postgres_ingress_from_backup" {
  metadata {
    name      = "allow-postgres-ingress-from-backup"
    namespace = "listmonk"
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
            app = "postgres-backup"
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
