############################################
# allow-pg-exporter-to-postgres (Egress)
############################################
resource "kubernetes_network_policy_v1" "listmonk_allow_pg_exporter_to_postgres" {
  metadata {
    name      = "allow-pg-exporter-to-postgres"
    namespace = kubernetes_namespace_v1.listmonk.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "prometheus-postgres-exporter"
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
  }

  depends_on = [kubernetes_network_policy_v1.listmonk_default_deny]
}

############################################
# allow-pg-exporter-into-postgres (Ingress)
############################################
resource "kubernetes_network_policy_v1" "listmonk_allow_pg_exporter_into_postgres" {
  metadata {
    name      = "allow-pg-exporter-into-postgres"
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
            "app.kubernetes.io/name" = "prometheus-postgres-exporter"
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

############################################
# allow-monitoring-to-pg-exporter (Ingress)
############################################
resource "kubernetes_network_policy_v1" "listmonk_allow_monitoring_to_pg_exporter" {
  metadata {
    name      = "allow-monitoring-to-pg-exporter"
    namespace = kubernetes_namespace_v1.listmonk.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "prometheus-postgres-exporter"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "monitoring"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = 9187
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.listmonk_default_deny]
}

