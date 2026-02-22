# Listmonk GitOps Deployment

Este Repositori contiene el despliegue del entorno para Listmonk. Tiene los siguientes componentes:

## Components
- Listmonk application
- PostgreSQL
- Cronjob+Pg_backup
- Mailpit (SMTP testing)
- Ingress-NGINX
- NetworkPolicies (zero-trust)
- Sealed Secrets
- Argocd
- argo-roloouts
- KPS (monit)
- Loki
- localtasck

## Requisitos Previos

### Herramientas Necesarias

- **kubectl** - Cliente de Kubernetes ([instalación](https://kubernetes.io/docs/tasks/tools/))
- **Helm** - Gestor de paquetes de Kubernetes ([instalación](https://helm.sh/docs/intro/install/))
- **Terraform** - 
- **AWScli** - 
- **Argo-rollouts** -

### Cluster Kubernetes

- **K3s** (recomendado para desarrollo)

### Configura Secrets

Hay 3 fichero que tienes que modificar y cifrar antes de ejecutar los scripts de instalacion.

Carpeta: infra/Terraform/secrets/

- aws-user.secret.plain_CONFIGURABLE.yaml
- grafana-admin.secret_plain_CONFIGURABLE.yaml
- postgres-secret-plain_CONFIGURABLE.yaml

Cifralo con sealed secret

kubeseal --controller-namespace kube-system --format yaml < XXXX-secret-plain.yaml > XXXX-sealedsecret.yaml

### Otros

- Es necesario añadir Renovate a tu repositorio


## Instalación Script

### 1. Instalar K3s (opcional)

```bash
./scripts/k3s_installation.sh
```

### 2. Configurar el cluster completo

```bash
./scripts/k3s_infra_deploy.sh
```

Este script automáticamente:

- Verifica requisitos y conexión al cluster
- Crea namespaces de localstack
- Instala localstack
- Aplica Terraform
    - Terraform crea namespaces
    - Terraform crea NetworkPolicies
    - Terraform instala stack Monitoring
    - Terraform crea los secretos
- Instala Argocd con helm
    - Argo despliega la aplicacion automaticamente (listmonk + postgres)
- Instala Argo-rollouts con helm
- Aplica listmonk como proyecto en Argocd
- Instala servicio de mail
- Instala webhook
- Crea S3 Buckets para backup y tftstate para terraform


### 3. Verificar estado del cluster

```bash
./scripts/k3s-status.sh
```

## Accesos y Servicios

### Aplicación

- listmonk: http://listmonk.local
- mail: http://mailpit.local

### Observabilidad

- Grafana: http://grafana.local

### Herramientas

- localstack: http://localstack.local
- argocd: http://argocd.local

---

# Listmonk GitOps Estrategia de depliegue (Renovate + ArgoCD + Argo Rollouts)

Este repositorio contiene el despliegue **GitOps** de la aplicación **Listmonk** en Kubernetes usando:

- **Kustomize**
- **ArgoCD**
- **Argo Rollouts (Blue/Green)**
- **Renovate (GitHub App)** para actualización automática de imágenes

#### Flujo:

**nueva imagen → PR GitOps → merge → despliegue Blue/Green**.

---
```
## Arquitectura del flujo

Repo app (listmonk)
        │
        │ build & push imagen vX.X.X
        ▼
GHCR (ghcr.io/ericnovales/listmonk_ericmod)
        │
        │ Renovate detecta nuevo tag
        ▼
Repo GitOps (este repo)
        │
        │ PR actualizando newTag en kustomization.yaml
        ▼
Merge del PR
        │
        ▼
ArgoCD sincroniza
        │
        ▼
Argo Rollouts (Blue/Green + análisis)
```

## Stack de Monitoring

### Herramientas Instaladas

- **Grafana** - Dashboards y visualización
- **Prometheus** - Recolección de métricas y alertas
- **Loki** - Sistema de logs centralizado
- **kube-state-metrics** - Métricas de estado del cluster
- **AlertManager** - Gestión de alertas
- **pg-exporter** - Métricas de Postgres
- Webhook - Conetener recivir alertas enviadas

### Dashboards Incluidos

- Estado Aplicacion
- Dashboards de Cluster
- Estado Database

## 📁 Estructura del Proyecto

```
listmonk_Kubernetes/
├── README.md
├── apps
│   └── listmonk
│       └── base
│           ├── analysistemplate-listmonk-smoke.yaml
│           ├── kustomization.yaml
│           ├── kustomization.yaml.backup
│           ├── listmonk-ingress.yaml
│           ├── listmonk-preview-ingress.yaml
│           ├── listmonk-preview-svc.yaml
│           ├── listmonk-rollout.yaml
│           ├── listmonk-svc.yaml
│           ├── listmonk-uploads-pvc.yaml
│           ├── postgres-backup-cronjob.yaml
│           ├── postgres-deploy.yaml
│           ├── postgres-pvc.yaml
│           └── postgres-svc.yaml
├── infra
│   ├── Terraform
│   │   ├── backend.tf
│   │   ├── kps.tf
│   │   ├── listmonk_network_policies.tf
│   │   ├── loki.tf
│   │   ├── mail_network_policies.tf
│   │   ├── namespaces.tf
│   │   ├── pg_exporter.tf
│   │   ├── pg_exporter_network_policies.tf
│   │   ├── postgres-backup_network_policies.tf
│   │   ├── promtail.tf
│   │   ├── providers.tf
│   │   ├── sealdsecret_aws_user.tf
│   │   ├── sealdsecret_grafana.tf
│   │   ├── sealdsecret_listmonk-postgres.tf
│   │   ├── secrets
│   │   │   ├── aws-user.sealedsecret.yaml
│   │   │   ├── aws-user.secret.plain_CONFIGURABLE.yaml
│   │   │   ├── grafana-admin.sealedsecret.yaml
│   │   │   ├── grafana-admin.secret_plain_CONFIGURABLE.yaml
│   │   │   ├── postgres-sealedsecret.yaml
│   │   │   └── postgres-secret-plain_CONFIGURABLE.yaml
│   │   └── serviceaccount.tf
│   ├── argocd
│   │   ├── argocd-app-listmonk.yaml
│   │   ├── argocd-project-listmonk.yaml
│   │   ├── values-argocd.yaml
│   │   └── values-rollouts.yaml
│   ├── localstack
│   │   ├── localstack-ingress.yaml
│   │   └── values-localstack.yaml
│   ├── mail
│   │   ├── kustomization.yaml
│   │   ├── mailpit-deploy.yaml
│   │   ├── mailpit-ingress.yaml
│   │   └── mailpit-svc.yaml
│   └── monitoring
│       ├── kps
│       │   ├── alerts
│       │   │   ├── Alerts.yaml
│       │   ├── values.alerting.yaml
│       │   ├── values.base.yaml
│       │   ├── values.dashboards.yaml
│       │   ├── values.datasources.yaml
│       │   ├── values.grafana.yaml
│       │   ├── values.ingress.yaml
│       │   └── webhook-test.yaml
│       ├── values-loki.yaml
│       ├── values-promtail.yaml
│       ├── values.postgres-exporter.yaml
│       └── webhook-receiver-python.yaml
├── renovate.json
└── scripts
    ├── destroy_all.sh
    ├── k3s-status.sh
    └── k3s_install_config_v3.sh

```

### Limpieza
Script para eliminar todo lo instalado. Cluster limpio.
Importante: Solo elimina si le pasas la variable ALLOW_DESTROY=1
```bash
ALLOW_DESTROY=1  ./scripts/clean_all_infra.sh
```

### Script con comandos utiles para a gestion
```bash
./scripts/help-commands.sh
```
