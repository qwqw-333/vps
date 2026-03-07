#!/usr/bin/env bash
# Sealed Secrets key management — backup/restore via 1Password
#
# Usage: ./sealed-secrets.sh <command>
#
# Commands:
#   backup    Export key pair from cluster and save to 1Password
#   restore   Import key pair from 1Password into cluster
#   status    Show key status in cluster and 1Password

set -euo pipefail

NAMESPACE="kube-system"
CONTROLLER_NAME="sealed-secrets"
OP_ITEM_NAME="Sealed Secrets Key"
# Store in the same vault as other project secrets; override via OP_VAULT env var
OP_VAULT="${OP_VAULT:-Personal}"

# Colors
C='\033[1;36m'
G='\033[1;32m'
R='\033[1;31m'
Y='\033[1;33m'
N='\033[0m'

usage() {
    printf "Usage: $0 <command>\n"
    printf "\n"
    printf "Commands:\n"
    printf "  backup    Export key pair from cluster and save to 1Password\n"
    printf "  restore   Import key pair from 1Password into cluster\n"
    printf "  status    Show key status in cluster and 1Password\n"
    printf "\n"
    printf "Environment:\n"
    printf "  OP_VAULT  1Password vault name (default: Personal)\n"
    exit 1
}

check_op() {
    if ! command -v op >/dev/null 2>&1; then
        printf "${R}Error: op (1Password CLI) not found${N}\n"
        printf "Install: brew install 1password-cli\n"
        exit 1
    fi
    if ! op whoami >/dev/null 2>&1; then
        printf "${R}Error: not signed in to 1Password${N}\n"
        printf "Run: op signin\n"
        exit 1
    fi
}

check_kubectl() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        printf "${R}Error: cannot connect to cluster${N}\n"
        exit 1
    fi
}

get_key_from_cluster() {
    kubectl get secret \
        -n "$NAMESPACE" \
        -l sealedsecrets.bitnami.com/sealed-secrets-key \
        -o yaml 2>/dev/null
}

cmd_backup() {
    printf "${C}=== Sealed Secrets Key Backup ===${N}\n\n"

    check_kubectl
    check_op

    # Check key exists in cluster
    local key_yaml
    key_yaml=$(get_key_from_cluster)
    if [ -z "$key_yaml" ] || echo "$key_yaml" | grep -q "items: \[\]"; then
        printf "${R}Error: no Sealed Secrets key found in cluster${N}\n"
        printf "Make sure the Sealed Secrets controller has been deployed and generated its key.\n"
        exit 1
    fi

    printf "Key found in cluster.\n"

    # Use a temp file — never left on disk after backup
    local temp_file
    temp_file=$(mktemp /tmp/sealed-secrets-key.XXXXXX.yaml)
    trap "rm -f $temp_file" EXIT

    echo "$key_yaml" > "$temp_file"

    # Save to 1Password as a document — overwrites if item already exists
    if op document get "$OP_ITEM_NAME" --vault="$OP_VAULT" >/dev/null 2>&1; then
        printf "Updating existing item in 1Password (vault: ${OP_VAULT})...\n"
        op document edit "$OP_ITEM_NAME" "$temp_file" --vault="$OP_VAULT"
    else
        printf "Creating new item in 1Password (vault: ${OP_VAULT})...\n"
        op document create "$temp_file" \
            --title="$OP_ITEM_NAME" \
            --vault="$OP_VAULT" \
            --tags="kubernetes,sealed-secrets"
    fi

    printf "\n${G}Backup complete.${N}\n"
    printf "  Item: ${OP_ITEM_NAME}\n"
    printf "  Vault: ${OP_VAULT}\n"
    printf "\nKey file was never written to disk (used temp file, cleaned up).\n"
}

cmd_restore() {
    printf "${C}=== Sealed Secrets Key Restore ===${N}\n\n"

    check_kubectl
    check_op

    # Check 1Password has the key
    if ! op document get "$OP_ITEM_NAME" --vault="$OP_VAULT" >/dev/null 2>&1; then
        printf "${R}Error: '${OP_ITEM_NAME}' not found in 1Password vault '${OP_VAULT}'${N}\n"
        printf "Run: task k8s:sealed-secrets:backup (on a working cluster first)\n"
        exit 1
    fi

    printf "Fetching key from 1Password...\n"

    local temp_file
    temp_file=$(mktemp /tmp/sealed-secrets-key.XXXXXX.yaml)
    trap "rm -f $temp_file" EXIT

    op document get "$OP_ITEM_NAME" --vault="$OP_VAULT" --out-file="$temp_file"

    # Strip status and resourceVersion fields to allow clean apply
    # (the exported secret contains these server-side fields)
    kubectl apply -f "$temp_file"

    # Restart controller so it picks up the imported key immediately
    if kubectl get deployment "$CONTROLLER_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        printf "Restarting Sealed Secrets controller...\n"
        kubectl rollout restart deployment/"$CONTROLLER_NAME" -n "$NAMESPACE"
        kubectl rollout status deployment/"$CONTROLLER_NAME" -n "$NAMESPACE" --timeout=60s
    fi

    printf "\n${G}Restore complete.${N}\n"
    printf "Sealed Secrets controller is now using the restored key pair.\n"
    printf "All existing SealedSecret manifests from Git should decrypt correctly.\n"
}

cmd_status() {
    printf "${C}=== Sealed Secrets Key Status ===${N}\n\n"

    printf "${C}Cluster:${N}\n"
    if ! kubectl cluster-info >/dev/null 2>&1; then
        printf "  Cannot connect to cluster\n"
    else
        local keys
        keys=$(kubectl get secret \
            -n "$NAMESPACE" \
            -l sealedsecrets.bitnami.com/sealed-secrets-key \
            --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$keys" -gt 0 ]; then
            printf "  ${G}Key found${N} (${keys} secret(s))\n"
            kubectl get secret \
                -n "$NAMESPACE" \
                -l sealedsecrets.bitnami.com/sealed-secrets-key \
                -o custom-columns="NAME:.metadata.name,CREATED:.metadata.creationTimestamp" 2>/dev/null
        else
            printf "  ${Y}No key found${N}\n"
        fi
    fi

    printf "\n${C}1Password (vault: ${OP_VAULT}):${N}\n"
    if ! command -v op >/dev/null 2>&1; then
        printf "  op CLI not installed\n"
    elif ! op whoami >/dev/null 2>&1; then
        printf "  Not signed in (run: op signin)\n"
    elif op document get "$OP_ITEM_NAME" --vault="$OP_VAULT" >/dev/null 2>&1; then
        local updated
        updated=$(op document get "$OP_ITEM_NAME" --vault="$OP_VAULT" --format=json 2>/dev/null \
            | grep -o '"updated_at":"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"/\1/' || echo "unknown")
        printf "  ${G}Backup found${N} (updated: ${updated})\n"
    else
        printf "  ${Y}No backup found${N}\n"
    fi
}

case "${1:-}" in
    backup)  cmd_backup ;;
    restore) cmd_restore ;;
    status)  cmd_status ;;
    *)       usage ;;
esac
