#!/bin/bash

set -euo pipefail

fail() {
    echo "$1" >&2
    exit 1
}

K=${KUBECTL_CMD:-"kubectl"}
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$($K config view -o json | jq -r '.contexts[] | select(.name == "'$($K config current-context)'") | .context.namespace // "default"')}
K="$K -n $DEPLOYMENT_NAMESPACE"

cd $(dirname "$0")

if ! command -v az >/dev/null 2>&1; then
    fail "Azure CLI (az) must be installed to create registry credentials"
fi

if [[ -z "${AZURE_CLIENT_ID:-}" || -z "${AZURE_CLIENT_SECRET:-}" || -z "${AZURE_TENANT_ID:-}" ]]; then
    fail "AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, and AZURE_TENANT_ID must be set to create Azure secrets"
fi

echo "Creating Azure service principal secret azure-service-principal"
$K delete --ignore-not-found secret azure-service-principal

DEFAULT_ACR_NAME=${ACR_NAME:-acrintellioptics}
DEFAULT_ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-${DEFAULT_ACR_NAME}.azurecr.io}

SECRET_ARGS=()
SECRET_ARGS+=(--from-literal=AZURE_CLIENT_ID="$AZURE_CLIENT_ID")
SECRET_ARGS+=(--from-literal=AZURE_CLIENT_SECRET="$AZURE_CLIENT_SECRET")
SECRET_ARGS+=(--from-literal=AZURE_TENANT_ID="$AZURE_TENANT_ID")
SECRET_ARGS+=(--from-literal=ACR_NAME="$DEFAULT_ACR_NAME")
SECRET_ARGS+=(--from-literal=ACR_LOGIN_SERVER="$DEFAULT_ACR_LOGIN_SERVER")

if [[ -n "${AZURE_STORAGE_CONNECTION_STRING:-}" ]]; then
    SECRET_ARGS+=(--from-literal=AZURE_STORAGE_CONNECTION_STRING="$AZURE_STORAGE_CONNECTION_STRING")
fi

$K create secret generic azure-service-principal "${SECRET_ARGS[@]}"

echo "Refreshing Azure Container Registry credentials"
KUBECTL_CMD="$K" ACR_NAME="$DEFAULT_ACR_NAME" ACR_LOGIN_SERVER="$DEFAULT_ACR_LOGIN_SERVER" ./refresh-ecr-login.sh

if ! $K get secret registry-credentials >/dev/null 2>&1; then
    fail "registry-credentials secret not found"
fi

if ! $K get secret azure-service-principal >/dev/null 2>&1; then
    fail "azure-service-principal secret not found"
fi

