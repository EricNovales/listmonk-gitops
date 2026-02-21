#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# Paths dinámicos (para mover a /scripts)
# -------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

#--------------------------------------------------
# Variables Localstack
#-------------------------------------------------
BUCKET_NAME_TERRAFORM="terraform-state"
S3_ENDPOINT="http://localstack.local"


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
# Funciones
# ----------------------------
need() { command -v "$1" >/dev/null || { log_err "Falta '$1'"; exit 1; }; }

ns_exists() { kubectl get ns "$1" >/dev/null 2>&1; }

ensure_ns() {
  local ns="$1"
  if ns_exists "$ns"; then
    log_warn "Namespace '$ns' ya existe (skip)"
  else
    log_apply "Creando namespace '$ns'"
    kubectl create namespace "$ns"
    log_ok "Namespace '$ns' creado"
  fi
}

wait_ns_pods_ready() {
  local ns="$1"

  ns_exists "$ns" || {
    log_warn "Namespace '$ns' no existe (skip wait)"
    return 0
  }

  # Si no hay pods, no esperamos
  local total
  total=$(kubectl -n "$ns" get pods --no-headers 2>/dev/null | wc -l | xargs)
  [[ "$total" -eq 0 ]] && return 0

  # Contar pods NO ready (best-effort)
  local not_ready
  not_ready=$(
    kubectl -n "$ns" get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[*].ready}{"\n"}{end}' 2>/dev/null \
    | awk '{
        for (i=1;i<=NF;i++) if ($i=="false") {c++ ; break}
      } END {print c+0}'
  )

  # Si todos están ready, no hacemos wait ni ensuciamos logs
  [[ "$not_ready" -eq 0 ]] && return 0

  log_apply "Esperando pods Ready en '$ns' (best-effort)..."
  kubectl -n "$ns" wait --for=condition=Ready pod --all --timeout=300s >/dev/null 2>&1 || true
  log_ok "Pods en '$ns' listos"
}

helm_release_exists() {
  local ns="$1" rel="$2"
  helm -n "$ns" status "$rel" >/dev/null 2>&1
}

helm_install_and_check() {
  local ns="$1" rel="$2" chart="$3"
  shift 3

  if helm_release_exists "$ns" "$rel"; then
    log_warn "Helm release '$rel' ya existe en ns '$ns' (skip)"
    return 0
  fi

  log_install "Helm release '$rel' en ns '$ns'"
  helm upgrade --install "$rel" "$chart" -n "$ns" "$@"

  # Validación (best-effort): release existe + pods ready
  if helm_release_exists "$ns" "$rel"; then
    kubectl -n "$ns" rollout status deploy --timeout=300s >/dev/null 2>&1 || true
    kubectl -n "$ns" rollout status statefulset --timeout=300s >/dev/null 2>&1 || true
    wait_ns_pods_ready "$ns"
    log_ok "Helm release '$rel' instalado y verificado"
  else
    log_err "Helm release '$rel' no aparece tras instalar."
    exit 1
  fi
}

# aplica solo si el recurso no existe (para cosas "únicas": AppProject, Application, webhook deploy...)
apply_if_missing() {
  local kind="$1" name="$2" ns="${3:-}" file="$4"
  if [[ -n "$ns" ]]; then
    if kubectl -n "$ns" get "$kind" "$name" >/dev/null 2>&1; then
      log_warn "${kind}/${name} ya existe en ns '$ns' (skip apply)"
      return 0
    fi
  else
    if kubectl get "$kind" "$name" >/dev/null 2>&1; then
      log_warn "${kind}/${name} ya existe (skip apply)"
      return 0
    fi
  fi

  log_apply "Aplicando $file"
  kubectl apply -f "$file"
  log_ok "Aplicado: $file"
}

kubectl_apply_file_checked() {
  local file="$1"

  log_apply "Aplicando $file"
  kubectl apply -f "$file"

  # Best-effort: intentar inferir namespace desde el manifest
  local ns
  ns="$(
    kubectl get -f "$file" -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null \
    | awk 'NF{print; exit}'
  )"
  [[ -n "$ns" ]] || ns="default"

  kubectl -n "$ns" rollout status deploy --timeout=300s >/dev/null 2>&1 || true
  kubectl -n "$ns" rollout status statefulset --timeout=300s >/dev/null 2>&1 || true
  wait_ns_pods_ready "$ns"

  log_ok "Aplicación verificada: $file"
}

kubectl_apply_kustomize_checked() {
  local dir="$1"

  log_apply "Aplicando kustomize: $dir"
  kubectl apply -k "$dir"

  # Best-effort: inferir namespace del output de kustomize
  local ns
  ns="$(
    kubectl kustomize "$dir" 2>/dev/null \
    | kubectl get -f - -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null \
    | awk 'NF{print; exit}'
  )"
  [[ -n "$ns" ]] || ns="default"

  kubectl -n "$ns" rollout status deploy --timeout=300s >/dev/null 2>&1 || true
  kubectl -n "$ns" rollout status statefulset --timeout=300s >/dev/null 2>&1 || true
  wait_ns_pods_ready "$ns"

  log_ok "Kustomize verificado: $dir"
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
  kubectl get ns ingress-nginx >/dev/null 2>&1 || return 1
  kubectl -n ingress-nginx get deploy/ingress-nginx-controller >/dev/null 2>&1 || return 1
  kubectl -n ingress-nginx get svc/ingress-nginx-controller >/dev/null 2>&1 || return 1
  return 0
}

install_ingress_nginx_if_missing() {
  if ingress_nginx_present; then
    log_warn "ingress-nginx ya está instalado (skip)"
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

# Bloquear Traefik y asegurar ingress-nginx
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

helm_install_and_check localstack localstack localstack/localstack \
  --version 0.6.27 -f "$PROJECT_ROOT/infra/localstack/values-localstack.yaml"

# wait si el deploy existe (mantengo tu validación original)
if kubectl -n localstack get deploy/localstack >/dev/null 2>&1; then
  kubectl -n localstack rollout status deploy/localstack --timeout=300s >/dev/null 2>&1 || true
  wait_ns_pods_ready localstack
fi

# ----------------------------
# Bucket terraform-state
# ----------------------------

if aws --endpoint-url="$S3_ENDPOINT" s3 ls "s3://$BUCKET_NAME_TERRAFORM" >/dev/null 2>&1; then
  log_warn "Bucket '$BUCKET_NAME_TERRAFORM' ya existe (skip)"
else
  log_apply "Creando bucket '$BUCKET_NAME_TERRAFORM'"
  if aws --endpoint-url="$S3_ENDPOINT" s3 mb "s3://$BUCKET_NAME_TERRAFORM" >/dev/null 2>&1; then
    log_ok "Bucket '$BUCKET_NAME_TERRAFORM' creado"
  else
    log_err "No se pudo crear el bucket '$BUCKET_NAME_TERRAFORM'"
    exit 1
  fi
fi

# ----------------------------
# 2) Terraform
# ----------------------------
echo "========== 2) Terraform =========="
if [[ -d "$PROJECT_ROOT/infra/Terraform" ]]; then
  pushd "$PROJECT_ROOT/infra/Terraform" >/dev/null

  terraform init
  terraform apply -auto-approve

  popd >/dev/null
else
  log_err "No existe infra/Terraform (ajusta la ruta en el script)"
  exit 1
fi

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

helm_install_and_check argocd argocd argo/argo-cd \
  -f "$PROJECT_ROOT/infra/argocd/values-argocd.yaml" --version 9.4.2

helm_install_and_check argo-rollouts argo-rollouts argo/argo-rollouts \
  -f "$PROJECT_ROOT/infra/argocd/values-rollouts.yaml" --version 2.40.5

# waits (mantengo tu validación original)
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s >/dev/null 2>&1 || true
wait_ns_pods_ready argocd
wait_ns_pods_ready argo-rollouts

apply_if_missing "appproject.argoproj.io" "listmonk" "argocd" "$PROJECT_ROOT/infra/argocd/argocd-project-listmonk.yaml"
apply_if_missing "application.argoproj.io" "listmonk" "argocd" "$PROJECT_ROOT/infra/argocd/argocd-app-listmonk.yaml"

wait_ns_pods_ready listmonk
echo

# ----------------------------
# 4) Mail + webhook receiver
# ----------------------------
echo "========== 4) Mail + Webhook =========="

# Mail (kustomize): si el namespace mail ya existe y hay deploy/mailpit, no lo reaplico
if ns_exists mail && kubectl -n mail get deploy/mailpit >/dev/null 2>&1; then
  log_warn "Mailpit ya existe (skip apply -k infra/mail)"
else
  kubectl_apply_kustomize_checked "$PROJECT_ROOT/infra/mail"
fi
wait_ns_pods_ready mail

# Webhook receiver: si existe deploy/webhook-receiver en monitoring, no reaplico
if ns_exists monitoring && kubectl -n monitoring get deploy/webhook-receiver >/dev/null 2>&1; then
  log_warn "webhook-receiver ya existe (skip apply)"
else
  kubectl_apply_file_checked "$PROJECT_ROOT/infra/monitoring/webhook-receiver-python.yaml"
fi
wait_ns_pods_ready monitoring

echo
echo "============================================================"
echo -e "${GREEN}BOOTSTRAP COMPLETADO${NC}"
echo "============================================================"
echo
echo -e "${BLUE}Namespaces:${NC}"
kubectl get ns
echo
echo -e "${BLUE}Helm releases:${NC}"
helm list -A
echo
echo -e "${BLUE}Pods:${NC}"
kubectl get pods -A
echo
echo -e "${BLUE}Buckets Localstack:${NC}"
aws --endpoint-url=$S3_ENDPOINT s3 ls || true
echo

