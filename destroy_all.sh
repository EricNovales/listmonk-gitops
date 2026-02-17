#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

if [[ "${ALLOW_DESTROY:-0}" != "1" ]]; then
  echo "❌ Bloqueado por seguridad."
  echo "   Ejecuta: ALLOW_DESTROY=1 $0"
  exit 1
fi

need() { command -v "$1" >/dev/null || { echo "❌ Falta '$1'"; exit 1; }; }

wait_ns_deleted() {
  NS=$1
  if kubectl get ns "$NS" >/dev/null 2>&1; then
    echo "⏳ Esperando eliminación del namespace '$NS'..."
    kubectl wait --for=delete ns/"$NS" --timeout=300s || true
  else
    echo "✅ Namespace '$NS' ya no existe"
  fi
}

wait_helm_deleted() {
  NS=$1
  REL=$2
  echo "⏳ Esperando a que Helm release '$REL' desaparezca..."
  for i in {1..60}; do
    if ! helm -n "$NS" status "$REL" >/dev/null 2>&1; then
      echo "✅ Release '$REL' eliminado"
      return 0
    fi
    sleep 5
  done
  echo "⚠️  Release '$REL' no desapareció a tiempo"
}

echo "🔎 Checks..."
need kubectl
need helm
need terraform
need aws

kubectl cluster-info >/dev/null
kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null
echo "✅ Cluster listo"
echo

# ============================================================
# 1️⃣ Argo App/Project
# ============================================================

echo "========== 1) Argo App/Project =========="

if kubectl -n argocd get application listmonk >/dev/null 2>&1; then
  kubectl delete -f infra/argocd/argocd-app-listmonk.yaml
  sleep 5
fi

if kubectl -n argocd get appproject listmonk >/dev/null 2>&1; then
  kubectl delete -f infra/argocd/argocd-project-listmonk.yaml
fi

echo

# ============================================================
# 2️⃣ Mail + Webhook + Listmonk + Postgres
# ============================================================

echo "========== 2) Mail + Webhook + Listmonk + Postgres =========="

if [[ -d infra/mail ]]; then
  kubectl delete -k infra/mail --ignore-not-found=true
fi

if [[ -d apps/listmonk/base ]]; then
  kubectl delete -k apps/listmonk/base --ignore-not-found=true
fi

if [[ -f infra/monitoring/webhook-receiver-python.yaml ]]; then
  kubectl delete -f infra/monitoring/webhook-receiver-python.yaml --ignore-not-found=true
fi

echo

# ============================================================
# 3️⃣ Helm
# ============================================================

echo "========== 3) Helm =========="

if helm -n argocd status argocd >/dev/null 2>&1; then
  helm -n argocd uninstall argocd
  wait_helm_deleted argocd argocd
fi

if helm -n argo-rollouts status argo-rollouts >/dev/null 2>&1; then
  helm -n argo-rollouts uninstall argo-rollouts
  wait_helm_deleted argo-rollouts argo-rollouts
fi

echo "ℹ️  Es normal que CRDs de Argo permanezcan (resource policy keep)."
echo

# ============================================================
# 4️⃣ Terraform destroy
# ============================================================

echo "========== 4) Terraform destroy =========="

if [[ -d infra/Terraform ]]; then
  pushd infra/Terraform
  terraform init
  terraform destroy -auto-approve
  popd >/dev/null
fi

wait_ns_deleted monitoring
wait_ns_deleted listmonk
echo

echo "============= 4) Localstack============="
# ============================================================
# Localstack
# ============================================================
if helm -n localstack status localstack >/dev/null 2>&1; then
  helm -n localstack uninstall localstack
  wait_helm_deleted localstack localstack
fi

# ============================================================
# 5️⃣ Namespaces finales
# ============================================================

echo "========== 5) Namespaces finales =========="

for ns in localstack; do
  kubectl delete ns "$ns" --ignore-not-found=true
  wait_ns_deleted "$ns"
done

echo

# ============================================================
# 6️⃣ Estado final
# ============================================================

echo "============================================================"
echo "✅ DESTROY COMPLETADO"
echo "============================================================"
echo
echo "📦 Namespaces:"
kubectl get ns
echo
echo "🚀 Helm releases:"
helm list -A || true
echo
echo "📊 Pods restantes:"
kubectl get pods -A
echo
echo "💾 PV/PVC:"
kubectl get pv || true
kubectl get pvc -A || true
echo

