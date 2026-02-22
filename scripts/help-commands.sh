#!/usr/bin/env bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

section() {
  echo -e "\n${BLUE}${BOLD}============================================================${NC}"
  echo -e "${BLUE}${BOLD}$1${NC}"
  echo -e "${BLUE}${BOLD}============================================================${NC}\n"
}

subsection() {
  echo -e "${CYAN}${BOLD}$1${NC}"
  echo -e "${CYAN}------------------------------------------------------------${NC}"
}

cmd() {
  echo -e "  ${GREEN}$1${NC}"
}

clear

section "LISTMONK KUBERNETES - COMANDOS ÚTILES"

subsection "KUBERNETES GENERAL"
cmd "kubectl get nodes -o wide"
cmd "kubectl get ns"
cmd "kubectl get pods -A"
cmd "kubectl describe pod <pod> -n <ns>"
cmd "kubectl logs <pod> -n <ns>"
cmd "kubectl rollout restart deploy/<name> -n <ns>"

subsection "INGRESS-NGINX"
cmd "kubectl -n ingress-nginx get pods"
cmd "kubectl -n ingress-nginx get svc"
cmd "kubectl get ingress -A"
cmd "kubectl describe ingress <name> -n <ns>"
cmd "kubectl -n ingress-nginx logs deploy/ingress-nginx-controller"

subsection "ARGOCD"
cmd "kubectl -n argocd get pods"
cmd "kubectl -n argocd get applications"
cmd "kubectl -n argocd describe application listmonk"
cmd "kubectl -n argocd port-forward svc/argocd-server 8080:443"

subsection "ARGO ROLLOUTS"
cmd "kubectl -n listmonk get rollout"
cmd "kubectl -n listmonk describe rollout listmonk"
cmd "kubectl -n listmonk argo rollouts status listmonk"
cmd "kubectl -n listmonk argo rollouts promote listmonk"

subsection "SEALED SECRETS"
cmd "kubectl get crd | grep sealed"
cmd "kubectl get sealedsecrets -A"
cmd "kubectl -n kube-system get pods | grep sealed"
cmd "kubectl describe sealedsecret <name> -n <ns>"

subsection "LOCALSTACK"
cmd "aws --endpoint-url=http://localstack.local s3 ls"
cmd "aws --endpoint-url=http://localstack.local s3 ls s3://terraform-state"
cmd "kubectl -n localstack get pods"

subsection "HELM"
cmd "helm list -A"
cmd "helm status <release> -n <ns>"
cmd "helm get values <release> -n <ns>"
cmd "helm uninstall <release> -n <ns>"

subsection "TERRAFORM"
cmd "terraform plan"
cmd "terraform apply -auto-approve"
cmd "terraform destroy -auto-approve"
cmd "terraform state list"

subsection "NETWORK POLICIES"
cmd "kubectl -n listmonk get networkpolicy"
cmd "kubectl -n listmonk describe networkpolicy <name>"

