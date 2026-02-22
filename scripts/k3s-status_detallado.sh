#!/usr/bin/env bash
set -euo pipefail

 export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

need() { command -v "$1" >/dev/null 2>&1 || { err "Falta '$1'"; exit 1; }; }

section() {
  echo
  echo "============================================================"
  echo -e "${BLUE}$1${NC}"
  echo "============================================================"
}

safe_run() {
  # Ejecuta y si falla no aborta el script
  set +e
  "$@"
  local rc=$?
  set -e
  return $rc
}

need kubectl
need helm
need aws

section "Cluster"
safe_run kubectl cluster-info >/dev/null 2>&1 && ok "kubectl conectado al cluster" || warn "No pude obtener cluster-info"
safe_run kubectl get nodes -o wide || warn "No pude listar nodes"
safe_run kubectl get ns || warn "No pude listar namespaces"

section "ingress-nginx"
if kubectl get ns ingress-nginx >/dev/null 2>&1; then
  safe_run kubectl -n ingress-nginx get pods
  safe_run kubectl -n ingress-nginx get svc
  safe_run kubectl get ingressclass
  ok "ingress-nginx: namespace presente"
else
  warn "ingress-nginx no está instalado (no existe ns ingress-nginx)"
fi

section "ArgoCD"
if kubectl get ns argocd >/dev/null 2>&1; then
  safe_run kubectl -n argocd get pods
  safe_run kubectl -n argocd get applications
  ok "ArgoCD: namespace presente"
else
  warn "ArgoCD no está instalado (no existe ns argocd)"
fi

section "Argo Rollouts (namespace argo-rollouts)"
if kubectl get ns argo-rollouts >/dev/null 2>&1; then
  safe_run kubectl -n argo-rollouts get pods
  ok "Argo Rollouts: namespace presente"
else
  warn "Argo Rollouts no está instalado (no existe ns argo-rollouts)"
fi

section "listmonk (Rollouts)"
if kubectl get ns listmonk >/dev/null 2>&1; then
  safe_run kubectl -n listmonk get rollout
  safe_run kubectl -n listmonk get pods
  ok "listmonk: namespace presente"
else
  warn "No existe ns listmonk"
fi

section "Localstack"
S3_ENDPOINT="${S3_ENDPOINT:-http://localstack.local}"
if kubectl get ns localstack >/dev/null 2>&1; then
  safe_run kubectl -n localstack get pods
  safe_run aws --endpoint-url="$S3_ENDPOINT" s3 ls && ok "S3 Localstack accesible en $S3_ENDPOINT" || warn "No pude listar buckets en $S3_ENDPOINT"
else
  warn "No existe ns localstack"
fi

section "Mail (mailpit)"
if kubectl get ns mail >/dev/null 2>&1; then
  safe_run kubectl -n mail get pods
  safe_run kubectl -n mail get svc
  ok "mail: namespace presente"
else
  warn "No existe ns mail"
fi

section "CronJobs"
safe_run kubectl get cronjobs -A || warn "No pude listar cronjobs"

section "Sealed Secrets"
if kubectl -n kube-system get deploy sealed-secrets-controller >/dev/null 2>&1; then
  safe_run kubectl -n kube-system get pods | grep -i sealed || true
  ok "Sealed Secrets detectado en kube-system (sealed-secrets-controller)"
elif kubectl get ns sealed-secrets >/dev/null 2>&1; then
  safe_run kubectl -n sealed-secrets get pods
  ok "Sealed Secrets detectado en ns sealed-secrets"
else
  warn "No detecto Sealed Secrets (ni kube-system ni sealed-secrets)"
fi

echo
ok "Status finalizado"

