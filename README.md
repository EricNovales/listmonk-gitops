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

