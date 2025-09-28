#!/bin/bash

set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}

ACR_NAME=${ACR_NAME:-"acrintellioptics"}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-"${ACR_NAME}.azurecr.io"}

if ! command -v az >/dev/null 2>&1; then
    echo "Azure CLI (az) is required to refresh registry credentials." >&2
    exit 1
fi

if ! az account show >/dev/null 2>&1; then
    if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_TENANT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" ]]; then
        echo "Logging in to Azure with the provided service principal credentials"
        az login --service-principal \
            --username "$AZURE_CLIENT_ID" \
            --password "$AZURE_CLIENT_SECRET" \
            --tenant "$AZURE_TENANT_ID" >/dev/null
    else
        echo "Azure CLI is not logged in and service principal credentials were not provided." >&2
        exit 1
    fi
fi

echo "Fetching Azure Container Registry credentials from $ACR_NAME"
ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query "username" -o tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv)

if [[ -z "$ACR_USERNAME" || -z "$ACR_PASSWORD" ]]; then
    echo "Failed to retrieve credentials for Azure Container Registry $ACR_NAME" >&2
    exit 1
fi

if command -v docker >/dev/null 2>&1; then
    echo "Logging docker into $ACR_LOGIN_SERVER"
    echo "$ACR_PASSWORD" | docker login \
        --username "$ACR_USERNAME" \
        --password-stdin \
        "$ACR_LOGIN_SERVER"
else
    echo "Docker is not installed. Skipping docker login." >&2
fi

echo "Updating registry-credentials secret with Azure Container Registry credentials"
$K delete --ignore-not-found secret registry-credentials
$K create secret docker-registry registry-credentials \
    --docker-server="$ACR_LOGIN_SERVER" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD"

echo "Stored Azure Container Registry credentials in secret registry-credentials"

