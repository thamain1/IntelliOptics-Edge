#!/bin/sh

set -eu

K=${KUBECTL_CMD:-"kubectl"}
# No need to explicitly pick the namespace - this normally runs in its own namespace

AZURE_REGISTRY_NAME=${AZURE_REGISTRY_NAME:-"acrintellioptics"}
AZURE_REGISTRY=${AZURE_REGISTRY:-"${AZURE_REGISTRY_NAME}.azurecr.io"}

# Try to obtain credentials from az cli if they are not provided explicitly.
if [ -z "${AZURE_REGISTRY_USERNAME:-}" ] || [ -z "${AZURE_REGISTRY_PASSWORD:-}" ]; then
    if command -v az >/dev/null 2>&1; then
        echo "Attempting to retrieve Azure Container Registry credentials using Azure CLI" >&2
        AZ_USERNAME_CMD=$(az acr credential show --name "$AZURE_REGISTRY_NAME" --query "username" -o tsv 2>/dev/null || true)
        AZ_PASSWORD_CMD=$(az acr credential show --name "$AZURE_REGISTRY_NAME" --query "passwords[0].value" -o tsv 2>/dev/null || true)
        if [ -n "${AZ_USERNAME_CMD}" ] && [ -n "${AZ_PASSWORD_CMD}" ]; then
            AZURE_REGISTRY_USERNAME=${AZURE_REGISTRY_USERNAME:-$AZ_USERNAME_CMD}
            AZURE_REGISTRY_PASSWORD=${AZURE_REGISTRY_PASSWORD:-$AZ_PASSWORD_CMD}
        fi
    fi
fi

if [ -z "${AZURE_REGISTRY_USERNAME:-}" ] || [ -z "${AZURE_REGISTRY_PASSWORD:-}" ]; then
    echo "Failed to resolve Azure Container Registry credentials" >&2
    exit 1
fi

echo "Fetched Azure Container Registry credentials"

if command -v docker >/dev/null 2>&1; then
    echo "$AZURE_REGISTRY_PASSWORD" | docker login \
        --username "$AZURE_REGISTRY_USERNAME" \
        --password-stdin \
        "$AZURE_REGISTRY"
else
    echo "Docker is not installed. Skipping docker ACR login." >&2
fi

$K delete --ignore-not-found secret acr-credentials

$K create secret docker-registry acr-credentials \
    --docker-server="$AZURE_REGISTRY" \
    --docker-username="$AZURE_REGISTRY_USERNAME" \
    --docker-password="$AZURE_REGISTRY_PASSWORD"

echo "Stored Azure Container Registry credentials in secret acr-credentials"
