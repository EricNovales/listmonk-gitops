#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Credenciales dummy para Localstack (útil para terraform backend s3 y awscli)
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# ----------------------------
# helpers
# ----------------------------
need() { command -v "$1" >/dev/null || { echo "❌ Falta '$1'"; exit 1; }; }

ns_exists() { kubectl get ns "$1" >/dev/null 2>&1; }

ensure_ns() {
  local ns="$1"
  if ns_exists "$ns"; then
    echo "✅ Namespace '$ns' ya existe"
  else
    echo "🆕 Creando namespace '$ns'"
    kubectl create namespace "$ns"
  fi
}

wait_ns_pods_ready() {
  local ns="$1"
  ns_exists "$ns" || { echo "ℹ️  Namespace '$ns' no existe (skip wait)"; return 0; }
  echo "⏳ Esperando pods Ready en '$ns' (best-effort)..."
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
    echo "✅ Helm release '$rel' ya existe en ns '$ns' (skip)"
  else
    echo "🧱 Instalando helm release '$rel' en ns '$ns'"
    helm upgrade --install "$rel" "$chart" -n "$ns" "$@"
  fi
}

# aplica solo si el recurso no existe (para cosas "únicas": AppProject, Application, webhook deploy...)
apply_if_missing() {
  local kind="$1" name="$2" ns="${3:-}" file="$4"
  if [[ -n "$ns" ]]; then
    if kubectl -n "$ns" get "$kind" "$name" >/dev/null 2>&1; then
      echo "✅ ${kind}/${name} ya existe en ns '$ns' (skip apply)"
      return 0
    fi
  else
    if kubectl get "$kind" "$name" >/dev/null 2>&1; then
      echo "✅ ${kind}/${name} ya existe (skip apply)"
      return 0
    fi
  fi
  echo "📌 Aplicando $file"
  kubectl apply -f "$file"
}

# ----------------------------
# checks
# ----------------------------
echo "🔎 Checks..."
need kubectl
need helm
need terraform
need aws

kubectl cluster-info >/dev/null
kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null

echo "✅ Cluster listo"
echo

# ----------------------------
# 1) Localstack + bucket
# ----------------------------
echo "========== 1) Localstack =========="
helm repo add localstack https://localstack.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

ensure_ns localstack

helm_install_if_missing localstack localstack localstack/localstack \
  --version 0.6.27 -f infra/localstack/values-localstack.yaml

# wait si lo acabamos de instalar o si el deploy existe
if kubectl -n localstack get deploy/localstack >/dev/null 2>&1; then
  kubectl -n localstack rollout status deploy/localstack --timeout=300s >/dev/null 2>&1 || true
  wait_ns_pods_ready localstack
fi

echo "🪣 Bucket terraform-state (si no existe)"
# Esto asume que Localstack está accesible en localhost:4566 desde tu host.
# Si no, habrá que hacer port-forward o usar endpoint diferente.
aws --endpoint-url=http://localstack.local s3 mb s3://terraform-state >/dev/null 2>&1 || true
aws --endpoint-url=http://localstack.local s3 ls || true
echo

# ----------------------------
# 2) Terraform
# ----------------------------
echo "========== 2) Terraform =========="
if [[ -d infra/Terraform ]]; then
  pushd infra/Terraform >/dev/null

  # “no tocar si ya está aplicado” no es trivial sin state; terraform ya es idempotente.
  # Si no hay cambios, no hará nada.
  terraform init
  terraform apply -auto-approve

  popd >/dev/null
else
  echo "❌ No existe infra/Terraform (ajusta la ruta en el script)"
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
  -f infra/argocd/values-argocd.yaml --version 9.4.2

helm_install_if_missing argo-rollouts argo-rollouts argo/argo-rollouts \
  -f infra/argocd/values-rollouts.yaml --version 2.40.5

# waits
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s >/dev/null 2>&1 || true
wait_ns_pods_ready argocd
wait_ns_pods_ready argo-rollouts

# Project y App: aplico solo si no existen
apply_if_missing "appproject.argoproj.io" "listmonk" "argocd" "infra/argocd/argocd-project-listmonk.yaml"
apply_if_missing "application.argoproj.io" "listmonk" "argocd" "infra/argocd/argocd-app-listmonk.yaml"

# espera a que listmonk aparezca (best-effort)
wait_ns_pods_ready listmonk
echo

# ----------------------------
# 4) Mail + webhook receiver
# ----------------------------
echo "========== 4) Mail + Webhook =========="

# Mail (kustomize): si el namespace mail ya existe y hay deploy/mailpit, no lo reaplico
if ns_exists mail && kubectl -n mail get deploy/mailpit >/dev/null 2>&1; then
  echo "✅ Mailpit ya existe (skip apply -k infra/mail)"
else
  echo "📬 Aplicando mail (kustomize)"
  kubectl apply -k infra/mail
fi
wait_ns_pods_ready mail

# Webhook receiver: si existe deploy/webhook-receiver en monitoring, no reaplico
if ns_exists monitoring && kubectl -n monitoring get deploy/webhook-receiver >/dev/null 2>&1; then
  echo "✅ webhook-receiver ya existe (skip apply)"
else
  echo "🪝 Aplicando webhook receiver"
  kubectl apply -f infra/monitoring/webhook-receiver-python.yaml
fi
wait_ns_pods_ready monitoring

echo
echo "============================================================"
echo "🎉 BOOTSTRAP COMPLETADO"
echo "============================================================"
echo
echo "📦 Namespaces:"
kubectl get ns
echo
echo "🚀 Helm releases:"
helm list -A
echo
echo "📊 Pods:"
kubectl get pods -A
echo
echo "🪣 Buckets Localstack:"
aws --endpoint-url=http://localstack s3 ls || true
echo

