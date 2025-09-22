#!/bin/bash

set -euo pipefail

fail() {
    echo "Error: $*" >&2
    exit 1
}

K=${KUBECTL_CMD:-"kubectl"}

ACR_NAME=${AZURE_CONTAINER_REGISTRY:-${ACR_NAME:-}}
ACR_LOGIN_SERVER=${AZURE_REGISTRY_SERVER:-${ACR_LOGIN_SERVER:-}}

if ! command -v az >/dev/null 2>&1; then
    fail "Azure CLI (az) is required but not installed"
fi

if ! command -v jq >/dev/null 2>&1; then
    fail "jq is required but not installed"
fi

if [ -z "${ACR_NAME}" ] && [ -z "${ACR_LOGIN_SERVER}" ]; then
    fail "Set ACR_NAME or AZURE_CONTAINER_REGISTRY (and optionally ACR_LOGIN_SERVER) before running this script"
fi

if [ -n "${AZURE_CLIENT_ID:-}" ] && [ -n "${AZURE_TENANT_ID:-}" ] && [ -n "${AZURE_CLIENT_SECRET:-}" ]; then
    echo "Logging into Azure using the provided service principal"
    az login --service-principal \
        --username "$AZURE_CLIENT_ID" \
        --password "$AZURE_CLIENT_SECRET" \
        --tenant "$AZURE_TENANT_ID" \
        >/dev/null
    if [ -n "${AZURE_SUBSCRIPTION_ID:-}" ]; then
        az account set --subscription "$AZURE_SUBSCRIPTION_ID" >/dev/null
    fi
fi

if [ -z "$ACR_LOGIN_SERVER" ] && [ -n "$ACR_NAME" ]; then
    ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)
fi

if [ -z "$ACR_LOGIN_SERVER" ]; then
    fail "Unable to determine the Azure Container Registry login server"
fi

if [ -z "$ACR_NAME" ]; then
    # Try to infer the registry name from the login server (e.g., myregistry.azurecr.io -> myregistry)
    ACR_NAME=${ACR_LOGIN_SERVER%%.azurecr.io}
fi

echo "Fetching ACR access token for ${ACR_LOGIN_SERVER}"
TOKEN_JSON=$(az acr login --name "$ACR_NAME" --expose-token --output json)

if [ -z "$TOKEN_JSON" ]; then
    fail "Failed to obtain ACR access token"
fi

ACR_USERNAME=$(echo "$TOKEN_JSON" | jq -r '.username // "00000000-0000-0000-0000-000000000000"')
ACR_PASSWORD=$(echo "$TOKEN_JSON" | jq -r '.password // .accessToken // ""')

if [ -z "$ACR_PASSWORD" ]; then
    fail "ACR access token did not contain a password/accessToken"
fi

if command -v docker >/dev/null 2>&1; then
    echo "$ACR_PASSWORD" | docker login \
        --username "$ACR_USERNAME" \
        --password-stdin \
        "$ACR_LOGIN_SERVER"
else
    echo "Docker is not installed. Skipping docker ACR login."
fi

$K delete --ignore-not-found secret registry-credentials

$K create secret docker-registry registry-credentials \
    --docker-server="$ACR_LOGIN_SERVER" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD"

echo "Stored Azure Container Registry credentials in secret registry-credentials"

