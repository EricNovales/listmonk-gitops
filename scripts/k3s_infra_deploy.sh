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
# logging (Colores)
# ----------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'
BOLD='\033[1m'
CYAN='\033[0;36m'
# -------------------------------------------------
# Trap global de error
# -------------------------------------------------
trap 'log_console "${RED}[ERROR]${NC} Bootstrap falló. Revisa el log: $BOOTSTRAP_LOG"; exit 1' ERR

# -------------------------------------------------
# Log global del bootstrap
# -------------------------------------------------
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"

TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
BOOTSTRAP_LOG="$LOG_DIR/bootstrap_${TIMESTAMP}.log"

# Guardar stdout/stderr originales (consola real)
exec 3>&1 4>&2

# Redirigir TODO lo demás al log
exec >"$BOOTSTRAP_LOG" 2>&1

# Eescribir en consola y también en log
log_console() {
#  echo -e "$1" >&3   # consola real
#  echo -e "$1"       # log (stdout ya redirigido)
local msg="$1"
  msg="${msg//$'\r'/}"
  while [[ "$msg" == *$'\n' ]]; do msg="${msg%$'\n'}"; done

  # Imprimir una sola vez con salto final controlado
  printf "%b\n" "$msg" >&3   # consola real
  printf "%b\n" "$msg"       # log
}

# Tipos de loggin

log_ok()      { log_console "${GREEN}[OK]${NC} $*"; }
log_install() { log_console "${BLUE}[INSTALLING]${NC} $*"; }
log_apply()   { log_console "${BLUE}[APPLYING]${NC} $*"; }
log_warn()    { log_console "${YELLOW}[WARNING]${NC} $*"; }
log_err()     { log_console "${RED}[ERROR]${NC} $*"; exit 1; }
log_info()    { log_console "${BLUE}[INFO]${NC} $*"; }

# Ejecucion comandos consola
run_summary() {
"$@" 2>&1 | tee >(cat >&3)
}


# ----------------------------
# Funciones
# ----------------------------

########### Verificación comandos ###########
need() { command -v "$1" >/dev/null || { log_err "Falta '$1'"; exit 1; }; }

########### Verificación namespaces ###########
ns_exists() { kubectl get ns "$1" >/dev/null 2>&1; }

########### Creación namespaces antes de Terraform ###########
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

########### Funcion de espera pods ###########
wait_ns_pods_ready() {
  local ns="$1"

  ns_exists "$ns" || {
    log_warn "Namespace '$ns' no existe (skip wait)"
    return 0
  }

  # Si no hay pods, no espera
  local total
  total=$(kubectl -n "$ns" get pods --no-headers 2>/dev/null | wc -l | xargs)
  [[ "$total" -eq 0 ]] && return 0

  # Contar pods NO ready
  local not_ready
  not_ready=$(
    kubectl -n "$ns" get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[*].ready}{"\n"}{end}' 2>/dev/null \
    | awk '{
        for (i=1;i<=NF;i++) if ($i=="false") {c++ ; break}
      } END {print c+0}'
  )

  # Si todos están ready, no hacemos wait
  [[ "$not_ready" -eq 0 ]] && return 0

  log_info "Esperando pods Ready en '$ns' ...."
  kubectl -n "$ns" wait --for=condition=Ready pod --all --timeout=300s >/dev/null 2>&1 || true
  log_ok "Pods en '$ns' listos"
}

########### Verificación si existe con Helm ###########
helm_release_exists() {
  local ns="$1" rel="$2"
  helm -n "$ns" status "$rel" >/dev/null 2>&1
}

########### Instalación con helm ###########
helm_install_and_check() {
  local ns="$1" rel="$2" chart="$3"
  shift 3

  if helm_release_exists "$ns" "$rel"; then
    log_warn "Helm release '$rel' ya existe en ns '$ns' (skip)"
    return 0
  fi

  log_install "Helm release '$rel' en ns '$ns'"
  helm upgrade --install "$rel" "$chart" -n "$ns" "$@"

  # Validación: release existe + pods ready
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

########### Verificacion especial para listmonk ###########

wait_rollout_ready() {
  local ns="$1" ro="$2"
  local timeout_sec="${3:-600}"

  local timeout_kubectl="${timeout_sec}s"

  # Esperar a que exista
  if ! kubectl -n "$ns" get rollout "$ro" >/dev/null 2>&1; then
    log_apply "Esperando a que exista rollout/$ro en '$ns'..."
    local start
    start="$(date +%s)"
    while ! kubectl -n "$ns" get rollout "$ro" >/dev/null 2>&1; do
      sleep 3
      if (( $(date +%s) - start > timeout_sec )); then
        log_err "Timeout esperando a que aparezca rollout/$ro"
        return 1
      fi
    done
  fi

  # Comprobar si ya está listo
  local desired available
  desired="$(kubectl -n "$ns" get rollout "$ro" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)"
  available="$(kubectl -n "$ns" get rollout "$ro" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)"

  if [[ "$available" -ge "$desired" ]]; then
    log_warn "rollout/$ro ya está listo (skip wait)"
    return 0
  fi

  log_apply "Esperando rollout/$ro..."
  kubectl -n "$ns" wait --for=condition=Available "rollout/$ro" --timeout="$timeout_kubectl" >/dev/null 2>&1 || true

  available="$(kubectl -n "$ns" get rollout "$ro" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)"

  if [[ "$available" -ge "$desired" ]]; then
    log_ok "rollout/$ro listo"
    return 0
  fi

  log_err "rollout/$ro no está listo tras esperar"
}


########### Función para ejecutar ficheros con Kubectl ###########
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

########### Función para ejecutar despligues con kubectl ###########
kubectl_apply_file_checked() {
  local file="$1"

  log_apply "Aplicando $file"
  kubectl apply -f "$file"

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

########### Función para ejecutar despligues con kubectl Kustomize ###########
kubectl_apply_kustomize_checked() {
  local dir="$1"

  log_apply "Aplicando kustomize: $dir"
  kubectl apply -k "$dir"

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

########### Verificación del Dns local ###########
ensure_local_dns_hosts() {
  local hosts="listmonk.local mailpit.local preview-listmonk.local grafana.local localstack.local argocd.local"
  local hosts_file="/etc/hosts"

  log_apply "Verificando DNS local ($hosts_file)"

  # Autodetectar IP del host
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  fi
  # Fallback: primera IP no-loopback de hostname -I
  if [[ -z "$ip" ]] && command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | tr ' ' '\n' | awk 'NF && $1 !~ /^127\./ {print $1; exit}')"
  fi
  [[ -n "$ip" ]] || { log_err "No pude autodetectar la IP del host"; exit 1; }

  [[ -w "$hosts_file" ]] || { log_err "No tengo permisos de escritura en $hosts_file (ejecuta como root o con sudo)"; exit 1; }

  # Si TODOS los hosts ya existen en /etc/hosts skip
  local h missing=0
  for h in $hosts; do
    if grep -Eq "^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+.*\b${h}\b" "$hosts_file"; then
      continue
    else
      missing=1
      break
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    log_warn "DNS local ya configurado (skip)"
    return 0
  fi

  # Añadimos UNA línea con la IP detectada y todos los hosts
  echo "$ip $hosts" >> "$hosts_file"

  # Verificación final (al menos uno con la IP recién añadida)
  if grep -Eq "^[[:space:]]*${ip//./\.}[[:space:]]+.*\blistmonk\.local\b" "$hosts_file"; then
    log_ok "DNS local configurado: $ip $hosts"
  else
    log_err "No se pudo verificar la entrada añadida en $hosts_file"
    exit 1
  fi
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
    log_err "Desactiva/borra Traefik y vuelve a ejecutar"
    exit 1
  fi
  log_ok "Traefik no detectado"
}

# verificacaión si existe nginx
ingress_nginx_present() {
  kubectl get ns ingress-nginx >/dev/null 2>&1 || return 1
  kubectl -n ingress-nginx get deploy/ingress-nginx-controller >/dev/null 2>&1 || return 1
  kubectl -n ingress-nginx get svc/ingress-nginx-controller >/dev/null 2>&1 || return 1
  return 0
}

# Añadir ingress-nginx sino existe
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

sealed_secrets_present() {
  
  if kubectl get ns sealed-secrets >/dev/null 2>&1; then
    kubectl -n sealed-secrets get deploy sealed-secrets >/dev/null 2>&1 && return 0
    kubectl -n sealed-secrets get deploy sealed-secrets-controller >/dev/null 2>&1 && return 0
  fi

  kubectl -n kube-system get deploy sealed-secrets-controller >/dev/null 2>&1 && return 0

  return 1
}

install_sealed_secrets_if_missing() {
  if sealed_secrets_present; then
    log_warn "sealed-secrets ya está instalado (skip)"
    return 0
  fi

  log_install "sealed-secrets no detectado. Instalando..."

  # Repo oficial del chart (bitnami-labs)
  helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets >/dev/null 2>&1 || true
  helm repo update >/dev/null

  # Instalación en namespace dedicado
  helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
    -n sealed-secrets --create-namespace

  # Validación best-effort, alineada con tu estilo
  kubectl -n sealed-secrets rollout status deploy/sealed-secrets --timeout=300s >/dev/null 2>&1 || true
  wait_ns_pods_ready sealed-secrets

  if sealed_secrets_present; then
    log_ok "sealed-secrets instalado y verificado"
  else
    log_err "Instalación/verificación de sealed-secrets fallida o incompleta."
    log_err "Revisa: kubectl -n sealed-secrets get pods,deploy,svc"
    exit 1
  fi
}



# ----------------------------
# checks
# ----------------------------
#log_apply "Validando Prerequisitios..."
need kubectl
need helm
need terraform
need aws
need kubectl-argo-rollouts

log_console ""
# ----------------------------
# 0) Cluster
# ----------------------------
log_console "========== 0) Estado del Cluster y Componentes  =========="

# Verificacion DNS-Local
ensure_local_dns_hosts

kubectl cluster-info >/dev/null
kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null

# Bloquear Traefik y Instalar/Verificar ingress-nginx
fail_if_traefik_present
install_ingress_nginx_if_missing

# Verificar/Instalar Sealed Secret
install_sealed_secrets_if_missing

log_ok "Cluster listo"

log_console ""
# ----------------------------
# 1) Localstack + bucket
# ----------------------------
log_console "========== 1) Localstack =========="
helm repo add localstack https://localstack.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
ensure_ns localstack
helm_install_and_check localstack localstack localstack/localstack \
  --version 0.6.27 -f "$PROJECT_ROOT/infra/localstack/values-localstack.yaml"

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
log_console ""
# ----------------------------
# 2) Terraform
# ----------------------------
log_console "========== 2) Terraform =========="

if [[ -d "$PROJECT_ROOT/infra/Terraform" ]]; then
  pushd "$PROJECT_ROOT/infra/Terraform" >/dev/null

  log_apply "Inicializando Terraform"
  terraform init -input=false -no-color >/dev/null
  
  log_apply "Comprobando cambios en infraestructura"
  TF_PLAN_EXIT=0
  terraform plan -detailed-exitcode -input=false -no-color >/dev/null || TF_PLAN_EXIT=$?


  if [[ $TF_PLAN_EXIT -eq 0 ]]; then
    log_ok "No hay cambios en la infraestructura"
  elif [[ $TF_PLAN_EXIT -eq 2 ]]; then
    log_apply "Cambios detectados. Aplicando..."
    terraform apply -auto-approve -input=false -no-color >/dev/null
    log_ok "Cambios aplicados correctamente"
  else
    log_err "Terraform plan falló"
  fi

  popd >/dev/null
else
  log_err "No existe infra/Terraform"
fi
wait_ns_pods_ready monitoring
log_console ""
# ----------------------------
#3) ArgoCD + Rollouts
# ----------------------------
log_console "========== 3) ArgoCD + Rollouts =========="
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null

ensure_ns argocd
ensure_ns argo-rollouts

log_info "${BLUE}Puede tardar varios minutos${NC}"

helm_install_and_check argocd argocd argo/argo-cd \
  -f "$PROJECT_ROOT/infra/argocd/values-argocd.yaml" --version 9.4.2

helm_install_and_check argo-rollouts argo-rollouts argo/argo-rollouts \
  -f "$PROJECT_ROOT/infra/argocd/values-rollouts.yaml" --version 2.40.5

wait_ns_pods_ready argocd
wait_ns_pods_ready argo-rollouts

apply_if_missing "appproject.argoproj.io" "listmonk" "argocd" "$PROJECT_ROOT/infra/argocd/argocd-project-listmonk.yaml"
apply_if_missing "application.argoproj.io" "listmonk" "argocd" "$PROJECT_ROOT/infra/argocd/argocd-app-listmonk.yaml"

wait_rollout_ready listmonk listmonk 600

log_console ""
# ----------------------------
# 4) Mail + webhook receiver
# ----------------------------
log_console "========== 4) Mail + Webhook =========="
# Mail (kustomize)
if ns_exists mail && kubectl -n mail get deploy/mailpit >/dev/null 2>&1; then
  log_warn "Mailpit ya existe (skip apply -k infra/mail)"
else
  kubectl_apply_kustomize_checked "$PROJECT_ROOT/infra/mail"
fi
wait_ns_pods_ready mail

# Webhook receiver
if ns_exists monitoring && kubectl -n monitoring get deploy/webhook-receiver >/dev/null 2>&1; then
  log_warn "webhook-receiver ya existe (skip apply)"
else
  kubectl_apply_file_checked "$PROJECT_ROOT/infra/monitoring/webhook-receiver-python.yaml"
fi
wait_ns_pods_ready monitoring
log_console ""
# ----------------------------
# Backup S3 Bucket
# ----------------------------
log_console "========== 5) Creación S3 Bucket para el Backup =========="
if aws --endpoint-url="$S3_ENDPOINT" s3 ls "s3://listmonk-postgres-backup" >/dev/null 2>&1; then
  log_warn "Bucket 'listmonk-postgres-backup' ya existe (skip)"
else
  log_apply "Creando bucket 'listmonk-postgres-backup'"
  if aws --endpoint-url="$S3_ENDPOINT" s3 mb "s3://listmonk-postgres-backup" >/dev/null 2>&1; then
    log_ok "Bucket 'listmonk-postgres-backup' creado"
  else
    log_err "No se pudo crear el bucket 'listmonk-postgres-backup'"
    exit 1
  fi
fi

log_console ""
log_console "============================================================"
log_console "${BLUE}${BOLD}BOOTSTRAP COMPLETADO${NC}"
log_console "============================================================"
log_console ""
log_console "${BLUE}Namespaces:${NC}"
run_summary kubectl get ns
log_console ""
log_console "${BLUE}Helm releases:${NC}"
run_summary helm list -A
log_console ""
log_console "${BLUE}Pods:${NC}"
run_summary kubectl get pods -A
log_console ""
log_console "${BLUE}Buckets Localstack:${NC}"
run_summary aws --endpoint-url=$S3_ENDPOINT s3 ls || true
log_console ""
log_console "${BLUE}Cron Jobs:${NC}"
run_summary kubectl get cronjobs -A
log_console ""
log_console "${BLUE}Rollouts listmonk:${NC}" 
run_summary kubectl -n listmonk get rollout || true

log_console ""
log_console "${BLUE}============================================================${NC}"
log_console "${BLUE}${BOLD}ACCESOS A SERVICIOS${NC}"
log_console "${BLUE}============================================================${NC}"
log_console ""

#Credenciales para Argocd
log_console "${BLUE}Credenciales Temporales Argocd${NC}"
log_console "User: admin"
log_console "Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
#log_console "Password: " run_summary kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo
log_warn "Cambialo en el primer login"

log_console ""
log_console "${CYAN}${BOLD}Aplicaciones:${NC}"
log_console "  ${GREEN}listmonk:${NC}      http://listmonk.local"
log_console "  ${GREEN}mail:${NC}          http://mailpit.local"
log_console ""
log_console "${CYAN}${BOLD}Observabilidad:${NC}"
log_console "  ${GREEN}Grafana:${NC}       http://grafana.local"
log_console ""
log_console "${CYAN}${BOLD}Herramientas:${NC}"
log_console "  ${GREEN}Localstack:${NC}    http://localstack.local"
log_console "  ${GREEN}ArgoCD:${NC}        http://argocd.local"
log_console ""
log_console "${BLUE}============================================================${NC}"
log_console ""
log_ok "Bootstrap completado"
log_ok "Log completo: $BOOTSTRAP_LOG"

