# Listmonk GitOps Deployment

Este Repositori contiene el despliegue del entorno para Listmonk. Tiene los siguientes componentes:

## Components
- Listmonk application
- PostgreSQL
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
- **Terrafomr** - 
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

### Otros

- Es necesario añadir Renovate a tu repositorio


## 🚀 Inicio Rápido

### 1. Instalar K3s (opcional pero recomendado)

```bash
./scripts/install-k3s.sh
```

### 2. Configurar el cluster completo

```bash
./scripts/setup-cluster.sh
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
./scripts/cluster-status.sh
```

## Accesos y Servicios

### Aplicación Web

- **URL:** Configurar Ingress o usar port-forward
- **Port-forward:** `kubectl port-forward -n la-huella-8 svc/app 8080:80`
- **Certificado SSL:** Autofirmado (válido por 40 días)

### Observabilidad

| Servicio       | URL                    | Credenciales | Descripción                |
| -------------- | ---------------------- | ------------ | -------------------------- |
| **Grafana**    | http://localhost:30000 | admin/admin  | Dashboards y visualización |
| **Prometheus** | http://localhost:30001 | -            | Métricas y alertas         |
| **Loki**       | http://localhost:30002 | -            | Logs centralizados         |


---

# Listmonk GitOps (Renovate + ArgoCD + Argo Rollouts)

Este repositorio contiene el despliegue **GitOps** de la aplicación **Listmonk** en Kubernetes usando:

- **Kustomize**
- **ArgoCD**
- **Argo Rollouts (Blue/Green)**
- **Renovate (GitHub App)** para actualización automática de imágenes

Automatizar el flujo:
**nueva imagen → PR GitOps → merge → despliegue Blue/Green**.

---

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

