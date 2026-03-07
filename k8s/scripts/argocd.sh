#!/usr/bin/env bash
# ArgoCD management — install via Helm, manage lifecycle
#
# Usage: ./argocd.sh <command>
#
# Commands:
#   install     Install ArgoCD (helm + root application)
#   uninstall   Uninstall ArgoCD
#   status      Show ArgoCD status
#   password    Get admin password

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")"
NAMESPACE="argocd"
CHART_VERSION="9.4.7"

# Colors
C='\033[1;36m'
G='\033[1;32m'
R='\033[1;31m'
N='\033[0m'

usage() {
    printf "Usage: $0 <command>\n"
    printf "\n"
    printf "Commands:\n"
    printf "  install     Install ArgoCD (helm + root application)\n"
    printf "  uninstall   Uninstall ArgoCD\n"
    printf "  status      Show ArgoCD status\n"
    printf "  password    Get admin password\n"
    exit 1
}

cmd_install() {
    printf "${C}=== ArgoCD Installation ===${N}\n\n"

    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    printf "Adding Argo Helm repository...\n"
    helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
    helm repo update argo

    printf "Installing ArgoCD ${CHART_VERSION}...\n"
    helm upgrade --install argocd argo/argo-cd \
        --namespace "$NAMESPACE" \
        --version "$CHART_VERSION" \
        --create-namespace \
        -f "$K8S_DIR/argocd/install/values.yaml" \
        --wait

    kubectl wait --for=condition=available deployment/argocd-server \
        -n "$NAMESPACE" --timeout=300s

    printf "Applying root application...\n"
    kubectl apply -f "$K8S_DIR/argocd/bootstrap/root.yaml"

    local password
    password=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

    printf "\n${G}=== ArgoCD installed ===${N}\n\n"
    if [ -n "$password" ]; then
        printf "  Admin password: ${password}\n"
    fi
    printf "  ArgoCD will now sync all apps from GitHub\n\n"
}

cmd_uninstall() {
    printf "${C}=== ArgoCD Uninstallation ===${N}\n\n"

    kubectl delete application root -n "$NAMESPACE" --ignore-not-found
    helm uninstall argocd -n "$NAMESPACE" --ignore-not-found || true
    kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=false

    printf "\n${G}Done.${N}\n"
}

cmd_status() {
    printf "${C}ArgoCD Status${N}\n\n"

    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        printf "ArgoCD not installed\n"
        exit 0
    fi

    printf "${C}Pods:${N}\n"
    kubectl get pods -n "$NAMESPACE" 2>/dev/null
    printf "\n"

    printf "${C}Applications:${N}\n"
    kubectl get applications -n "$NAMESPACE" 2>/dev/null || printf "  (none)\n"
}

cmd_password() {
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        printf "${R}ArgoCD not installed${N}\n"
        exit 1
    fi

    local password
    password=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

    if [ -n "$password" ]; then
        printf "Admin password: ${password}\n"
    else
        printf "Initial password not found — may have been deleted or a custom password was set.\n"
    fi
}

case "${1:-}" in
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    status)    cmd_status ;;
    password)  cmd_password ;;
    *)         usage ;;
esac
