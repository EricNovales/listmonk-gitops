# Listmonk GitOps Deployment

This repository contains a GitOps-based Kubernetes deployment of Listmonk.

## Components
- Listmonk application
- PostgreSQL
- Mailpit (SMTP testing)
- Ingress-NGINX
- NetworkPolicies (zero-trust)
- Sealed Secrets

## Structure
- listmonk/base: core application manifests
- mail/base: mailpit manifests

## Deployment
```bash
kubectl apply -k listmonk/base
kubectl apply -k mail/base

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

