#!/usr/bin/env bash
set -euo pipefail

# =====================
# CONFIGURACIÓN
# =====================
NS_INGRESS="ingress-nginx"
NS_ARGO="argocd"
NS_APP="listmonk"
NS_MON="monitoring"
NS_SEALED="kube-system"
NS_ROLLOUTS="argo-rollouts"

TIMEOUT="30s"

FAIL=0
WARN=0

# Colores
OKC="\033[0;32m"
WARC="\033[0;33m"
FAILC="\033[0;31m"
INFOC="\033[0;36m"
NC="\033[0m"

print_ok()   { echo -e "${OKC}[ OK ]${NC} $1"; }
print_warn() { echo -e "${WARC}[WARN]${NC} $1"; WARN=$((WARN+1)); }
print_fail() { echo -e "${FAILC}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }

# =====================
# CHECKS
# =====================

check_kubectl() {
  kubectl version >/dev/null 2>&1 \
    && print_ok "Acceso al cluster" \
    || { print_fail "Sin acceso al cluster"; exit 2; }
}

check_nodes() {
  local bad
  bad=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"{print $1}')
  [[ -z "$bad" ]] \
    && print_ok "Nodos Ready" \
    || print_fail "Nodos NO Ready: $bad"
}

check_namespace() {
  local ns="$1"
  kubectl get ns "$ns" >/dev/null 2>&1 \
    && print_ok "Namespace $ns existe" \
    || print_warn "Namespace $ns no existe"
}

check_pods_health() {
  local ns="$1" name="$2"

  # Si el namespace no existe, no tiene sentido chequear pods
  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    print_warn "$name: namespace $ns no existe"
    return 0
  fi

  local bad
  bad=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null \
    | awk '$3 ~ /(CrashLoopBackOff|Error|Pending|ImagePullBackOff|ErrImagePull|Unknown)/{print $1}')

  [[ -z "$bad" ]] \
    && print_ok "$name pods sanos" \
    || print_fail "$name pods con errores"
}

check_component() {
  local ns="$1"
  local component="$2"
  local match="$3"

  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    print_warn "$component: namespace $ns no existe"
    return 0
  fi

  local pods
  pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -i "$match" || true)

  if [[ -z "$pods" ]]; then
    print_warn "$component no encontrado"
    return 0
  fi

  local bad
  bad=$(echo "$pods" | awk '$3 ~ /(CrashLoopBackOff|Error|Pending|ImagePullBackOff|ErrImagePull|Unknown)/{print $1}')

  [[ -z "$bad" ]] \
    && print_ok "$component OK" \
    || print_fail "$component con errores"
}


check_deployments_ready() {
  local ns="$1" name="$2"

  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    print_warn "$name: namespace $ns no existe"
    return 0
  fi

  # Si no hay deployments, lo marcamos como warning (para no dar falso FAIL)
  if ! kubectl get deploy -n "$ns" --no-headers >/dev/null 2>&1; then
    print_warn "$name: no hay deployments en $ns"
    return 0
  fi

  if kubectl rollout status deploy -n "$ns" --timeout="$TIMEOUT" >/dev/null 2>&1; then
    print_ok "$name deployments OK"
  else
    print_fail "$name deployments NO listos"
  fi
}

check_ingress() {
  kubectl get ingress -A >/dev/null 2>&1 \
    && print_ok "Ingress resources accesibles" \
    || print_warn "No hay ingress o error al listar"
}

check_pvc() {
  local pending
  pending=$(kubectl get pvc -A --no-headers 2>/dev/null | awk '$4=="Pending"{print}')
  [[ -z "$pending" ]] \
    && print_ok "PVCs OK" \
    || print_fail "PVCs en Pending"
}

# =====================
# EJECUCIÓN
# =====================

echo -e "${INFOC}=== Estado del cluster K3s ===${NC}"

check_kubectl
check_nodes
check_pvc

echo -e "\n${INFOC}--- Infraestructura ---${NC}"
check_namespace "$NS_INGRESS"
check_pods_health "$NS_INGRESS" "Ingress"
check_ingress

echo -e "\n${INFOC}--- GitOps ---${NC}"
check_namespace "$NS_ARGO"
check_pods_health "$NS_ARGO" "ArgoCD"
check_deployments_ready "$NS_ARGO" "ArgoCD"

echo -e "\n${INFOC}--- Rollouts (Argo Rollouts) ---${NC}"
check_namespace "$NS_ROLLOUTS"
check_pods_health "$NS_ROLLOUTS" "Argo Rollouts"
check_deployments_ready "$NS_ROLLOUTS" "Argo Rollouts"

echo -e "\n${INFOC}--- Aplicación (Listmonk) ---${NC}"
check_namespace "$NS_APP"
check_pods_health "$NS_APP" "Listmonk"
check_deployments_ready "$NS_APP" "Listmonk"

echo -e "\n${INFOC}--- Monitoring ---${NC}"
check_namespace "$NS_MON"

check_component "$NS_MON" "Prometheus" "prometheus"
check_component "$NS_MON" "Alertmanager" "alertmanager"
check_component "$NS_MON" "Grafana" "grafana"
check_component "$NS_MON" "Loki" "loki"
check_component "$NS_MON" "Promtail" "promtail"
check_component "$NS_MON" "kube-state-metrics" "kube-state-metrics"
check_component "$NS_MON" "Webhook" "webhook"

echo -e "\n${INFOC}--- Seguridad ---${NC}"
check_namespace "$NS_SEALED"
check_pods_health "$NS_SEALED" "Sealed Secrets"

echo
echo -e "${INFOC}=== Resumen ===${NC}"
[[ "$FAIL" -gt 0 ]] && print_fail "Errores: $FAIL | Warnings: $WARN" && exit 1
[[ "$WARN" -gt 0 ]] && print_warn "Warnings: $WARN" && exit 0
print_ok "Cluster saludable ✅"

