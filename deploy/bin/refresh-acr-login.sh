#!/bin/bash

set -e

K=${KUBECTL_CMD:-"kubectl"}
# No need to explicitly pick the namespace - this normally runs in its own namespace

ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:?"ACR_LOGIN_SERVER must be set (e.g. myregistry.azurecr.io)"}
AZURE_REGISTRY_USERNAME=${AZURE_REGISTRY_USERNAME:?"AZURE_REGISTRY_USERNAME must be set"}
AZURE_REGISTRY_PASSWORD=${AZURE_REGISTRY_PASSWORD:?"AZURE_REGISTRY_PASSWORD must be set"}

echo "Fetched Azure Container Registry credentials"

if command -v docker >/dev/null 2>&1; then
    echo "$AZURE_REGISTRY_PASSWORD" | docker login \
        --username "$AZURE_REGISTRY_USERNAME" \
        --password-stdin  \
        "$ACR_LOGIN_SERVER"
else
    echo "Docker is not installed. Skipping docker ACR login."
fi

$K delete --ignore-not-found secret registry-credentials

$K create secret docker-registry registry-credentials \
    --docker-server="$ACR_LOGIN_SERVER" \
    --docker-username="$AZURE_REGISTRY_USERNAME" \
    --docker-password="$AZURE_REGISTRY_PASSWORD"

echo "Stored ACR credentials in secret registry-credentials"

