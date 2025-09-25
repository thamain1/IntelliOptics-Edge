#!/bin/bash

set -euo pipefail

fail() {
    echo "$1" >&2
    exit 1
}

K=${KUBECTL_CMD:-"kubectl"}
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$($K config view -o json | jq -r '.contexts[] | select(.name == "'$($K config current-context)'") | .context.namespace // "default"')}
# Update K to include the deployment namespace
K="$K -n $DEPLOYMENT_NAMESPACE"

cd $(dirname "$0")

AZURE_REGISTRY_NAME=${AZURE_REGISTRY_NAME:-"acrintellioptics"}
AZURE_REGISTRY=${AZURE_REGISTRY:-"${AZURE_REGISTRY_NAME}.azurecr.io"}

# Attempt to retrieve credentials via Azure CLI if not already provided
if [ -z "${AZURE_REGISTRY_USERNAME:-}" ] || [ -z "${AZURE_REGISTRY_PASSWORD:-}" ]; then
    if command -v az >/dev/null 2>&1; then
        echo "Attempting to retrieve Azure Container Registry credentials using Azure CLI"
        AZ_USERNAME_CMD=$(az acr credential show --name "$AZURE_REGISTRY_NAME" --query "username" -o tsv 2>/dev/null || true)
        AZ_PASSWORD_CMD=$(az acr credential show --name "$AZURE_REGISTRY_NAME" --query "passwords[0].value" -o tsv 2>/dev/null || true)
        if [ -n "$AZ_USERNAME_CMD" ] && [ -n "$AZ_PASSWORD_CMD" ]; then
            AZURE_REGISTRY_USERNAME=${AZURE_REGISTRY_USERNAME:-$AZ_USERNAME_CMD}
            AZURE_REGISTRY_PASSWORD=${AZURE_REGISTRY_PASSWORD:-$AZ_PASSWORD_CMD}
        fi
    fi
fi

if [ -z "${AZURE_REGISTRY_USERNAME:-}" ] || [ -z "${AZURE_REGISTRY_PASSWORD:-}" ]; then
    fail "No Azure Container Registry credentials found"
fi

# Create a generic secret to store the credentials for automation jobs
$K delete --ignore-not-found secret azure-registry-credentials
$K create secret generic azure-registry-credentials \
    --from-literal=username="$AZURE_REGISTRY_USERNAME" \
    --from-literal=password="$AZURE_REGISTRY_PASSWORD"

# Refresh the docker-registry secret using the retrieved credentials
AZURE_REGISTRY_USERNAME="$AZURE_REGISTRY_USERNAME" \
AZURE_REGISTRY_PASSWORD="$AZURE_REGISTRY_PASSWORD" \
AZURE_REGISTRY="$AZURE_REGISTRY" \
AZURE_REGISTRY_NAME="$AZURE_REGISTRY_NAME" \
KUBECTL_CMD="$K" \
    ./refresh-acr-login.sh

# Verify secrets have been properly created
if ! $K get secret azure-registry-credentials >/dev/null 2>&1; then
    fail "azure-registry-credentials secret not found"
fi

if ! $K get secret acr-credentials >/dev/null 2>&1; then
    fail "acr-credentials secret not found"
fi
