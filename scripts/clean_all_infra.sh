#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# -------------------------------------------------
# Colores básicos
# -------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -------------------------------------------------
# Logging
# -------------------------------------------------
log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*" 1>&2; }

# -------------------------------------------------
# Paths dinámicos (para mover a /scripts)
# -------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Seguridad
if [[ "${ALLOW_DESTROY:-0}" != "1" ]]; then
  log_err "Bloqueado por seguridad."
  log_info "Ejecuta: ALLOW_DESTROY=1 $0"
  exit 1
fi

# -------------------------------------------------
# Funciones
# -------------------------------------------------

# Verificar si comando existe
need() { command -v "$1" >/dev/null || { log_err "Falta '$1'"; exit 1; }; }

# Espera a que elimine el namespace
wait_ns_deleted() {
  local NS="$1"
  if kubectl get ns "$NS" >/dev/null 2>&1; then
    log_info "Esperando eliminación del namespace '$NS'..."
    kubectl wait --for=delete "ns/$NS" --timeout=300s || true
  else
    log_ok "Namespace '$NS' ya no existe"
  fi
}

# Espera a que elimine los Pods por Helm
wait_helm_deleted() {
  local NS="$1"
  local REL="$2"
  log_info "Esperando a que Helm release '$REL' desaparezca..."
  for i in {1..60}; do
    if ! helm -n "$NS" status "$REL" >/dev/null 2>&1; then
      log_ok "Release '$REL' eliminado"
      return 0
    fi
    sleep 5
  done
  log_warn "Release '$REL' no desapareció a tiempo"
}

# Verificacion de Clustter y Comandos

log_info "Checks..."
need kubectl
need helm
need terraform
need aws

kubectl cluster-info >/dev/null
kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null
log_ok "Cluster listo"
echo

# ============================================================
# 1) Argo App/Project
# ============================================================

log_info "========== 1) Argo App/Project =========="

if kubectl -n argocd get application listmonk >/dev/null 2>&1; then
  kubectl delete -f "$PROJECT_ROOT/infra/argocd/argocd-app-listmonk.yaml" || true
  sleep 5
fi

if kubectl -n argocd get appproject listmonk >/dev/null 2>&1; then
  kubectl delete -f "$PROJECT_ROOT/infra/argocd/argocd-project-listmonk.yaml" || true
fi

echo

# ============================================================
# 2) Mail + Webhook + Listmonk + Postgres
# ============================================================

echo "========== 2) Mail + Webhook + Listmonk + Postgres =========="

if [[ -d "$PROJECT_ROOT/infra/mail" ]]; then
  kubectl delete -k "$PROJECT_ROOT/infra/mail" --ignore-not-found=true
fi

if [[ -d "$PROJECT_ROOT/apps/listmonk/base" ]]; then
  kubectl delete -k "$PROJECT_ROOT/apps/listmonk/base" --ignore-not-found=true
fi

if [[ -f "$PROJECT_ROOT/infra/monitoring/webhook-receiver-python.yaml" ]]; then
  kubectl delete -f "$PROJECT_ROOT/infra/monitoring/webhook-receiver-python.yaml" --ignore-not-found=true
fi

echo

# ============================================================
# 3) Helm
# ============================================================

log_info "========== 3) Helm =========="

if helm -n argocd status argocd >/dev/null 2>&1; then
  helm -n argocd uninstall argocd
  wait_helm_deleted argocd argocd
fi

if helm -n argo-rollouts status argo-rollouts >/dev/null 2>&1; then
  helm -n argo-rollouts uninstall argo-rollouts
  wait_helm_deleted argo-rollouts argo-rollouts
fi

echo

# ============================================================
# 4) Terraform destroy
# ============================================================

echo "========== 4) Terraform destroy =========="

if [[ -d "$PROJECT_ROOT/infra/Terraform" ]]; then
  pushd "$PROJECT_ROOT/infra/Terraform" >/dev/null
  terraform init
  terraform destroy -auto-approve
  popd >/dev/null
fi

wait_ns_deleted monitoring
wait_ns_deleted listmonk
echo

# ============================================================
# 5) Localstack
# ============================================================

echo "========== 5) Localstack =========="

if helm -n localstack status localstack >/dev/null 2>&1; then
  helm -n localstack uninstall localstack
  wait_helm_deleted localstack localstack
fi

# ============================================================
# 6) Namespaces finales
# ============================================================

echo "========== 6) Namespaces finales =========="

for ns in localstack; do
  kubectl delete ns "$ns" --ignore-not-found=true
  wait_ns_deleted "$ns"
done

echo

# ============================================================
# 7) Estado final
# ============================================================

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}DESTROY COMPLETADO${NC}"
echo -e "${GREEN}============================================================${NC}"
echo

echo -e "${BLUE}Namespaces:${NC}"
kubectl get ns
echo

echo -e "${BLUE}Helm releases:${NC}"
helm list -A || true
echo

echo -e "${BLUE}Pods restantes:${NC}"
kubectl get pods -A
echo

echo -e "${BLUE}PV/PVC:${NC}"
kubectl get pv || true
kubectl get pvc -A || true
echo

