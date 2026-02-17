#!/usr/bin/env bash
set -euo pipefail

# =========================
# k3s cleanup script
# =========================
# Uso:
#   ALLOW_CLEANUP=1 ./k3s-cleanup.sh
# Opciones:
#   DRY_RUN=1         -> solo muestra lo que haría
#   PURGE_PV=1        -> intenta borrar PVs/PVCs (y algunos restos) asociados a namespaces eliminados
#   FORCE_NS=1        -> fuerza borrado de namespaces bloqueados (quita finalizers)
#   KEEP_NS="a b c"   -> lista de namespaces a NO borrar (separados por espacios)

: "${DRY_RUN:=0}"
: "${PURGE_PV:=0}"
: "${FORCE_NS:=0}"
: "${KEEP_NS:=}"
: "${ALLOW_CLEANUP:=0}"
: "${KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"
export KUBECONFIG

echo "🔎 KUBECONFIG=${KUBECONFIG}"
helm env | grep -E 'KUBECONFIG|KUBE' || true


if [[ "${ALLOW_CLEANUP}" != "1" ]]; then
  echo "❌ Bloqueado por seguridad. Ejecuta así:"
  echo "   ALLOW_CLEANUP=1 $0"
  exit 1
fi

run() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[DRY_RUN] $*"
  else
    eval "$@"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

if ! have kubectl; then
  echo "❌ 'kubectl' no está instalado/en PATH"
  exit 1
fi

if ! have helm; then
  echo "⚠️  'helm' no está instalado/en PATH. Saltaré pasos de helm (solo haré kubectl)."
fi

CTX="$(kubectl config current-context 2>/dev/null || true)"
echo "🔎 Contexto kubectl actual: ${CTX:-"(desconocido)"}"
echo "⚙️  DRY_RUN=${DRY_RUN} PURGE_PV=${PURGE_PV} FORCE_NS=${FORCE_NS}"
echo

# -------------------------
# helpers
# -------------------------
ns_in_keep_list() {
  local ns="$1"
  for k in ${KEEP_NS}; do
    [[ "$k" == "$ns" ]] && return 0
  done
  return 1
}

namespace_exists() {
  kubectl get ns "$1" >/dev/null 2>&1
}

delete_namespace() {
  local ns="$1"
  if ns_in_keep_list "$ns"; then
    echo "⏭️  KEEP_NS: no borro namespace '$ns'"
    return 0
  fi
  if namespace_exists "$ns"; then
    echo "🧹 Borrando namespace: $ns"
    run "kubectl delete ns \"$ns\" --wait=false"
  else
    echo "✅ Namespace '$ns' no existe (ok)"
  fi
}

force_remove_ns_finalizers() {
  local ns="$1"
  if ! namespace_exists "$ns"; then return 0; fi
  echo "🛠️  Forzando eliminación de finalizers en namespace '$ns' (si está atascado)"
  # Quita finalizers del objeto Namespace
  run "kubectl get ns \"$ns\" -o json | sed 's/\"finalizers\": \\[[^]]*\\]/\"finalizers\": []/g' | kubectl replace --raw /api/v1/namespaces/$ns/finalize -f -"
}

helm_uninstall_if_present() {
  local release="$1"
  local ns="$2"
  if ! have helm; then return 0; fi
  if helm -n "$ns" status "$release" >/dev/null 2>&1; then
    echo "🧽 Helm uninstall: $release (ns=$ns)"
    run "helm -n \"$ns\" uninstall \"$release\""
  else
    echo "✅ Helm release '$release' no existe en ns '$ns' (ok)"
  fi
}

delete_manifest_if_exists() {
  # Para manifests aplicados con kubectl apply -f <url|file>
  local ref="$1"
  echo "🧽 kubectl delete -f $ref (si existe)"
  run "kubectl delete -f \"$ref\" --ignore-not-found=true"
}

delete_kustomize_if_possible() {
  local path="$1"
  local wait_ns="${2:-}"

  if [[ -d "$path" ]]; then
    echo "🧽 kubectl delete -k $path"
    run "kubectl delete -k \"$path\" --ignore-not-found=true"

    if [[ -n "$wait_ns" ]] && kubectl get ns "$wait_ns" >/dev/null 2>&1; then
      echo "⏳ Esperando a que el namespace '$wait_ns' se elimine tras delete -k..."
      kubectl wait --for=delete "ns/$wait_ns" --timeout=300s 2>/dev/null || true
    fi
  else
    echo "ℹ️  No encuentro ruta local '$path' (saltando delete -k). Si existe en tu máquina, ejecuta:"
    echo "    kubectl delete -k $path"
  fi
}


purge_pvs_for_namespaces() {
  # Intenta borrar PVCs/PVs asociados a namespaces objetivo.
  # En k3s (local-path), puede quedar basura en /var/lib/rancher/k3s/storage/ en los nodos: eso es manual.
  local namespaces=("$@")

  echo "🔥 PURGE_PV=1: intentando borrar PVCs en namespaces: ${namespaces[*]}"
  for ns in "${namespaces[@]}"; do
    if ns_in_keep_list "$ns"; then
      echo "⏭️  KEEP_NS: no purgeo PVC/PV para '$ns'"
      continue
    fi
    if namespace_exists "$ns"; then
      echo "🧨 Borrando PVCs en ns=$ns"
      run "kubectl -n \"$ns\" delete pvc --all --ignore-not-found=true --wait=false"
    else
      echo "ℹ️  Namespace '$ns' no existe; intento borrar PVs que apunten a claims antiguos (si los hay)."
    fi
  done

  echo "🔥 Buscando PVs con claimRef a namespaces objetivo y borrándolos"
  # Lista PV + ns claimRef
  local pvlist
  pvlist="$(kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.claimRef.namespace}{"\n"}{end}' 2>/dev/null || true)"
  if [[ -z "$pvlist" ]]; then
    echo "✅ No hay PVs (o no tengo permisos para listarlos)."
    return 0
  fi

  while IFS=$'\t' read -r pv ns; do
    [[ -z "$pv" ]] && continue
    for target in "${namespaces[@]}"; do
      if [[ "$ns" == "$target" ]] && ! ns_in_keep_list "$ns"; then
        echo "🧨 Borrando PV '$pv' (claimRef.namespace=$ns)"
        run "kubectl delete pv \"$pv\" --ignore-not-found=true --wait=false"
      fi
    done
  done <<< "$pvlist"

  cat <<'EOF'
⚠️  Nota k3s/local-path:
- Aunque borres PV/PVC, puede quedar directorio en los nodos:
  /var/lib/rancher/k3s/storage/
  Eso se limpia en cada nodo manualmente (con cuidado).
EOF
}

# -------------------------
# 1) Sealed Secrets
# -------------------------
#
#
#
# 1) Sealed Secrets (KEEP)
echo "========== 1) Sealed Secrets (KEEP) =========="
echo "✅ No se elimina Sealed Secrets (controller, CRDs ni objetos SealedSecret)."
echo "ℹ️  Si algún día quieres borrar SOLO sealedsecrets de un namespace concreto:"
echo "    kubectl -n <ns> delete sealedsecret --all"
# -------------------------
# 2) Helm releases (Argo / Monitoring / Exporters)
# -------------------------
echo
echo "========== 2) Helm releases =========="

# ArgoCD + Rollouts
helm_uninstall_if_present "argocd" "argocd"
helm_uninstall_if_present "argo-rollouts" "argo-rollouts"

# Monitoring
helm_uninstall_if_present "kps" "monitoring"
helm_uninstall_if_present "loki" "monitoring"
helm_uninstall_if_present "promtail" "monitoring"

# Postgres Exporter lo instalaste en ns=listmonk con release=pg-exporter
helm_uninstall_if_present "pg-exporter" "listmonk"

#Localstack
helm_uninstall_if_present "localstack" "localstack"


# -------------------------
# 3) Manifests sueltos (NetworkPolicy, Webhook receiver, Argo apps/projects)
# -------------------------
echo
echo "========== 3) Manifests sueltos (si están en tu repo local) =========="

# Estos paths vienen de tu descripción. Si existen, hacemos delete -f/-k; si no, te imprimimos el comando.
if [[ -f "infra/argocd/argocd-project-listmonk.yaml" ]]; then
  echo "🧽 Borrando ArgoCD Project listmonk"
  run "kubectl delete -f infra/argocd/argocd-project-listmonk.yaml --ignore-not-found=true"
else
  echo "ℹ️  Si existe en tu máquina:"
  echo "    kubectl delete -f infra/argocd/argocd-project-listmonk.yaml --ignore-not-found=true"
fi

if [[ -f "infra/argocd/argocd-app-listmonk.yaml" ]]; then
  echo "🧽 Borrando ArgoCD App listmonk"
  run "kubectl delete -f infra/argocd/argocd-app-listmonk.yaml --ignore-not-found=true"
else
  echo "ℹ️  Si existe en tu máquina:"
  echo "    kubectl delete -f infra/argocd/argocd-app-listmonk.yaml --ignore-not-found=true"
fi

# NetworkPolicies para exporter (patrón)
shopt -s nullglob
NP_FILES=(infra/monitoring/networkpolicy*exporter*.yaml)
shopt -u nullglob

if (( ${#NP_FILES[@]} > 0 )); then
  echo "🧽 Borrando NetworkPolicies del exporter (${#NP_FILES[@]} ficheros)"
  for f in "${NP_FILES[@]}"; do
    run "kubectl delete -f \"$f\" --ignore-not-found=true"
  done
else
  echo "ℹ️  No encuentro ficheros infra/monitoring/networkpolicy*exporter*.yaml"
  echo "    Si existen en tu máquina, bórralos con:"
  echo "    for f in infra/monitoring/networkpolicy*exporter*.yaml; do kubectl delete -f \"$f\" --ignore-not-found=true; done"
fi



# Webhook receiver
if [[ -f "infra/monitoring/webhook-receiver-python.yaml" ]]; then
  echo "🧽 Borrando webhook receiver"
  run "kubectl delete -f infra/monitoring/webhook-receiver-python.yaml --ignore-not-found=true"
else
  echo "ℹ️  Si existe en tu máquina:"
  echo "    kubectl delete -f infra/monitoring/webhook-receiver-python.yaml --ignore-not-found=true"
fi

# -------------------------
# 4) Kustomize apps (Mailpit, Listmonk)
# -------------------------
echo
echo "========== 4) Kustomize (si tienes el repo local) =========="
delete_kustomize_if_possible "infra/mail" "mail"
delete_kustomize_if_possible "apps/base/Manual/listmonk" "listmonk"

# -------------------------
# 5) Namespaces (borrado "gordo")
# -------------------------
echo
echo "========== 5) Namespaces =========="
TARGET_NAMESPACES=( "mail" "listmonk" "argocd" "argo-rollouts" "monitoring" "localstack" )

# Opcional: purga PVC/PV antes de borrar namespaces
if [[ "${PURGE_PV}" == "1" ]]; then
  purge_pvs_for_namespaces "${TARGET_NAMESPACES[@]}"
fi

for ns in "${TARGET_NAMESPACES[@]}"; do
  delete_namespace "$ns"
done

# -------------------------
# 6) Forzar namespaces atascados (finalizers)
# -------------------------
echo
echo "========== 6) Forzar borrado (si procede) =========="
if [[ "${FORCE_NS}" == "1" ]]; then
  for ns in "${TARGET_NAMESPACES[@]}"; do
    force_remove_ns_finalizers "$ns"
  done
else
  echo "ℹ️  Si algún namespace se queda en Terminating, re-ejecuta con:"
  echo "    FORCE_NS=1 ALLOW_CLEANUP=1 $0"
fi

# -------------------------
# 7) Resumen / verificación
# -------------------------
echo
echo "========== 7) Verificación =========="
echo "🔎 Pods restantes relevantes (filtrado rápido):"
run "kubectl get pods -A | egrep -i 'sealed|argocd|rollout|prometheus|alertmanager|grafana|loki|promtail|mailpit|listmonk|localstack|pg-exporter|webhook' || true"

echo
echo "🔎 Helm releases (todas):"
if have helm; then
  run "helm list -A || true"
else
  echo "helm no disponible."
fi

echo
echo "✅ Cleanup terminado."

