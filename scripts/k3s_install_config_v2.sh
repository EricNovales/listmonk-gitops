#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# Paths dinámicos (para mover a /scripts)
# -------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Credenciales dummy para Localstack (útil para terraform backend s3 y awscli)
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# ----------------------------
# logging (sin iconos + colores)
# ----------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_ok()      { echo -e "${GREEN}[OK]${NC} $*"; }
log_install() { echo -e "${BLUE}[INSTALLING]${NC} $*"; }
log_apply()   { echo -e "${BLUE}[APPLYING]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_err()     { echo -e "${RED}[ERROR]${NC} $*" 1>&2; }

# ----------------------------
# helpers
# ----------------------------
need() { command -v "$1" >/dev/null || { log_err "Falta '$1'"; exit 1; }; }

ns_exists() { kubectl get ns "$1" >/dev/null 2>&1; }

ensure_ns() {
  local ns="$1"
  if ns_exists "$ns"; then
    log_ok "Namespace '$ns' ya existe"
  else
    log_apply "Creando namespace '$ns'"
    kubectl create namespace "$ns"
  fi
}

wait_ns_pods_ready() {
  local ns="$1"
  ns_exists "$ns" || { log_warn "Namespace '$ns' no existe (skip wait)"; return 0; }
  log_apply "Esperando pods Ready en '$ns' (best-effort)..."
  kubectl -n "$ns" wait --for=condition=Ready pod --all --timeout=300s >/dev/null 2>&1 || true
}

helm_release_exists() {
  local ns="$1" rel="$2"
  helm -n "$ns" status "$rel" >/dev/null 2>&1
}

helm_install_if_missing() {
  local ns="$1" rel="$2" chart="$3"
  shift 3
  if helm_release_exists "$ns" "$rel"; then
    log_ok "Helm release '$rel' ya existe en ns '$ns' (skip)"
  else
    log_install "Helm release '$rel' en ns '$ns'"
    helm upgrade --install "$rel" "$chart" -n "$ns" "$@"
  fi
}

# aplica solo si el recurso no existe (para cosas "únicas": AppProject, Application, webhook deploy...)
apply_if_missing() {
  local kind="$1" name="$2" ns="${3:-}" file="$4"
  if [[ -n "$ns" ]]; then
    if kubectl -n "$ns" get "$kind" "$name" >/dev/null 2>&1; then
      log_ok "${kind}/${name} ya existe en ns '$ns' (skip apply)"
      return 0
    fi
  else
    if kubectl get "$kind" "$name" >/dev/null 2>&1; then
      log_ok "${kind}/${name} ya existe (skip apply)"
      return 0
    fi
  fi
  log_apply "Aplicando $file"
  kubectl apply -f "$file"
}

# ----------------------------
# ingress-nginx / traefik checks
# ----------------------------
detect_traefik() {
  # Señales típicas:
  kubectl get ns traefik >/dev/null 2>&1 && return 0
  kubectl -n kube-system get deploy traefik >/dev/null 2>&1 && return 0
  kubectl get ingressclass traefik >/dev/null 2>&1 && return 0
  # k3s: Traefik como HelmChart
  kubectl -n kube-system get helmcharts.helm.cattle.io traefik >/dev/null 2>&1 && return 0
  kubectl -n kube-system get helmcharts.helm.cattle.io traefik-crd >/dev/null 2>&1 && return 0
  return 1
}

fail_if_traefik_present() {
  if detect_traefik; then
    log_err "Detectado Traefik en el cluster."
    log_err "Este script SOLO funciona con ingress-nginx."
    log_err "Desactiva/borra Traefik y vuelve a ejecutar (en k3s suele ser --disable traefik al instalar)."
    exit 1
  fi
  log_ok "Traefik no detectado"
}

ingress_nginx_present() {
  # Validación algo más robusta para evitar falsos positivos
  kubectl get ns ingress-nginx >/dev/null 2>&1 || return 1
  kubectl -n ingress-nginx get deploy/ingress-nginx-controller >/dev/null 2>&1 || return 1
  kubectl -n ingress-nginx get svc/ingress-nginx-controller >/dev/null 2>&1 || return 1
  return 0
}

install_ingress_nginx_if_missing() {
  if ingress_nginx_present; then
    log_ok "ingress-nginx ya está instalado"
    return 0
  fi

  log_install "ingress-nginx no detectado. Instalando..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo update >/dev/null

  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    -n ingress-nginx --create-namespace

  # best-effort waits (como el resto del script)
  kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s >/dev/null 2>&1 || true
  wait_ns_pods_ready ingress-nginx

  if ingress_nginx_present; then
    log_ok "ingress-nginx instalado y verificado"
  else
    log_err "Instalación/verificación de ingress-nginx fallida o incompleta."
    log_err "Revisa: kubectl -n ingress-nginx get pods,deploy,svc"
    exit 1
  fi
}

# ----------------------------
# checks
# ----------------------------
log_apply "Checks..."
need kubectl
need helm
need terraform
need aws

kubectl cluster-info >/dev/null
kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null

# NUEVO: bloquear Traefik y asegurar ingress-nginx
fail_if_traefik_present
install_ingress_nginx_if_missing

log_ok "Cluster listo"
echo

# ----------------------------
# 1) Localstack + bucket
# ----------------------------
echo "========== 1) Localstack =========="
helm repo add localstack https://localstack.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

ensure_ns localstack

helm_install_if_missing localstack localstack localstack/localstack \
  --version 0.6.27 -f "$PROJECT_ROOT/infra/localstack/values-localstack.yaml"

# wait si lo acabamos de instalar o si el deploy existe
if kubectl -n localstack get deploy/localstack >/dev/null 2>&1; then
  kubectl -n localstack rollout status deploy/localstack --timeout=300s >/dev/null 2>&1 || true
  wait_ns_pods_ready localstack
fi

log_apply "Bucket terraform-state (si no existe)"
# Esto asume que Localstack está accesible en localhost:4566 desde tu host.
# Si no, habrá que hacer port-forward o usar endpoint diferente.
aws --endpoint-url=http://localstack.local s3 mb s3://terraform-state >/dev/null 2>&1 || true
aws --endpoint-url=http://localstack.local s3 ls || true
echo

# ----------------------------
# 2) Terraform
# ----------------------------
echo "========== 2) Terraform =========="
if [[ -d "$PROJECT_ROOT/infra/Terraform" ]]; then
  pushd "$PROJECT_ROOT/infra/Terraform" >/dev/null

  # “no tocar si ya está aplicado” no es trivial sin state; terraform ya es idempotente.
  # Si no hay cambios, no hará nada.
  terraform init
  terraform apply -auto-approve

  popd >/dev/null
else
  log_err "No existe infra/Terraform (ajusta la ruta en el script)"
  exit 1
fi

# Esperas best-effort a namespaces que dices que crea terraform
wait_ns_pods_ready monitoring
wait_ns_pods_ready listmonk
echo

# ----------------------------
# 3) ArgoCD + Rollouts
# ----------------------------
echo "========== 3) ArgoCD + Rollouts =========="
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null

ensure_ns argocd
ensure_ns argo-rollouts

helm_install_if_missing argocd argocd argo/argo-cd \
  -f "$PROJECT_ROOT/infra/argocd/values-argocd.yaml" --version 9.4.2

helm_install_if_missing argo-rollouts argo-rollouts argo/argo-rollouts \
  -f "$PROJECT_ROOT/infra/argocd/values-rollouts.yaml" --version 2.40.5

# waits
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s >/dev/null 2>&1 || true
wait_ns_pods_ready argocd
wait_ns_pods_ready argo-rollouts

# Project y App: aplico solo si no existen
apply_if_missing "appproject.argoproj.io" "listmonk" "argocd" "$PROJECT_ROOT/infra/argocd/argocd-project-listmonk.yaml"
apply_if_missing "application.argoproj.io" "listmonk" "argocd" "$PROJECT_ROOT/infra/argocd/argocd-app-listmonk.yaml"

# espera a que listmonk aparezca (best-effort)
wait_ns_pods_ready listmonk
echo

# ----------------------------
# 4) Mail + webhook receiver
# ----------------------------
echo "========== 4) Mail + Webhook =========="

# Mail (kustomize): si el namespace mail ya existe y hay deploy/mailpit, no lo reaplico
if ns_exists mail && kubectl -n mail get deploy/mailpit >/dev/null 2>&1; then
  log_ok "Mailpit ya existe (skip apply -k infra/mail)"
else
  log_apply "Aplicando mail (kustomize)"
  kubectl apply -k "$PROJECT_ROOT/infra/mail"
fi
wait_ns_pods_ready mail

# Webhook receiver: si existe deploy/webhook-receiver en monitoring, no reaplico
if ns_exists monitoring && kubectl -n monitoring get deploy/webhook-receiver >/dev/null 2>&1; then
  log_ok "webhook-receiver ya existe (skip apply)"
else
  log_apply "Aplicando webhook receiver"
  kubectl apply -f "$PROJECT_ROOT/infra/monitoring/webhook-receiver-python.yaml"
fi
wait_ns_pods_ready monitoring

echo
echo "============================================================"
echo -e "${GREEN}BOOTSTRAP COMPLETADO${NC}"
echo "============================================================"
echo
echo "Namespaces:"
kubectl get ns
echo
echo "Helm releases:"
helm list -A
echo
echo "Pods:"
kubectl get pods -A
echo
echo "Buckets Localstack:"
aws --endpoint-url=http://localstack.local s3 ls || true
echo

