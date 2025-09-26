#!/bin/bash

set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}

current_namespace=$($K config view -o json | jq -r \
    ".contexts[] | select(.name == \"$($K config current-context)\") | .context.namespace // \"default\"")
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$current_namespace}
K="$K -n $DEPLOYMENT_NAMESPACE"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

# Refresh the docker-registry secret using Azure Container Registry credentials
KUBECTL_CMD="$K" ./refresh-acr-login.sh

AZURE_STORAGE_CONNECTION_STRING=${AZURE_STORAGE_CONNECTION_STRING:-""}
AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT:-""}
AZURE_STORAGE_RESOURCE_GROUP=${AZURE_STORAGE_RESOURCE_GROUP:-""}
AZURE_STORAGE_CONTAINER=${AZURE_STORAGE_CONTAINER:-"pinamod"}

if [ -z "$AZURE_STORAGE_CONNECTION_STRING" ] && [ -n "$AZURE_STORAGE_ACCOUNT" ]; then
    if [ -n "$AZURE_STORAGE_RESOURCE_GROUP" ]; then
        AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
            --name "$AZURE_STORAGE_ACCOUNT" \
            --resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
            --query connectionString -o tsv)
    else
        AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
            --name "$AZURE_STORAGE_ACCOUNT" \
            --query connectionString -o tsv)
    fi
fi

if [ -z "$AZURE_STORAGE_CONNECTION_STRING" ]; then
    echo "Azure storage connection string not provided. Set AZURE_STORAGE_CONNECTION_STRING or provide AZURE_STORAGE_ACCOUNT." >&2
    exit 1
fi

$K delete --ignore-not-found secret azure-storage
$K create secret generic azure-storage \
    --from-literal=connection_string="$AZURE_STORAGE_CONNECTION_STRING" \
    --from-literal=container="$AZURE_STORAGE_CONTAINER"

if ! $K get secret registry-credentials >/dev/null 2>&1; then
    echo "registry-credentials secret not found" >&2
    exit 1
fi

echo "Created azure-storage secret with container $AZURE_STORAGE_CONTAINER"
