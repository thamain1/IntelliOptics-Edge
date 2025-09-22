#!/bin/bash

set -euo pipefail

fail() {
    echo "Error: $*" >&2
    exit 1
}

K=${KUBECTL_CMD:-"kubectl"}
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$($K config view -o json | jq -r '.contexts[] | select(.name == "'$($K config current-context)'") | .context.namespace // "default"')}
# Update K to include the deployment namespace
K="$K -n $DEPLOYMENT_NAMESPACE"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

# Run the refresh-ecr-login.sh, telling it to use the configured KUBECTL_CMD
KUBECTL_CMD="$K" "$SCRIPT_DIR/refresh-ecr-login.sh"

REQUIRED_SP_VARS=(AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_CLIENT_SECRET)
for var in "${REQUIRED_SP_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        fail "$var must be set to create the Azure service principal secret"
    fi
done

if [ -z "${AZURE_STORAGE_CONNECTION_STRING:-}" ]; then
    fail "AZURE_STORAGE_CONNECTION_STRING must be set to create the Azure storage secret"
fi

$K delete --ignore-not-found secret azure-service-principal
CREATE_ARGS=(
    --from-literal=AZURE_CLIENT_ID="${AZURE_CLIENT_ID}"
    --from-literal=AZURE_TENANT_ID="${AZURE_TENANT_ID}"
    --from-literal=AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}"
)
if [ -n "${AZURE_SUBSCRIPTION_ID:-}" ]; then
    CREATE_ARGS+=(--from-literal=AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}")
fi
$K create secret generic azure-service-principal "${CREATE_ARGS[@]}"

$K delete --ignore-not-found secret azure-storage-credentials
$K create secret generic azure-storage-credentials \
    --from-literal=AZURE_STORAGE_CONNECTION_STRING="${AZURE_STORAGE_CONNECTION_STRING}"

# Verify secrets have been properly created
if ! $K get secret registry-credentials >/dev/null 2>&1; then
    fail "registry-credentials secret not found"
fi

if ! $K get secret azure-service-principal >/dev/null 2>&1; then
    fail "azure-service-principal secret not found"
fi

if ! $K get secret azure-storage-credentials >/dev/null 2>&1; then
    fail "azure-storage-credentials secret not found"
fi

