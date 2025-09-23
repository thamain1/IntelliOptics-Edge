#!/bin/sh

# Part two of getting Azure credentials set up.
# This script runs in a minimal container with kubectl and the Azure CLI, and applies the credentials to the cluster.

# We do two things:
# 1. Create a secret with the Azure credentials file produced by the first stage.
# 2. Create a secret with Docker registry credentials for the Azure Container Registry (ACR).

# We wait for the credentials to be written to the shared volume by the previous script.
TIMEOUT=60  # Maximum time to wait in seconds
FILE="/shared/done"

echo "Waiting up to $TIMEOUT seconds for $FILE to exist..."

i=0
while [ $i -lt $TIMEOUT ]; do
    if [ -f "$FILE" ]; then
        echo "✅ File $FILE found! Continuing..."
        break
    fi
    sleep 1
    i=$((i + 1))
done

# If the loop completed without breaking, the file did not appear
if [ ! -f "$FILE" ]; then
    echo "❌ Error: File $FILE did not appear within $TIMEOUT seconds." >&2
    exit 1
fi


echo "Creating Kubernetes secrets..."

set -a
. /shared/azure.env
set +a

if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not found; installing via az aks install-cli"
    az aks install-cli >/dev/null
fi

for required in \
    AZURE_CLIENT_ID \
    AZURE_CLIENT_SECRET \
    AZURE_TENANT_ID \
    AZURE_STORAGE_ACCOUNT \
    AZURE_STORAGE_KEY \
    AZURE_STORAGE_CONTAINER \
    ACR_LOGIN_SERVER \
    ACR_NAME; do
    if [ -z "${!required}" ]; then
        echo "Environment variable $required not found in /shared/azure.env" >&2
        exit 1
    fi
done

if [ -n "$AZURE_CLIENT_ID" ] && [ -n "$AZURE_CLIENT_SECRET" ] && [ -n "$AZURE_TENANT_ID" ]; then
    echo "Logging into Azure using provided service principal"
    az login --service-principal \
        --username "$AZURE_CLIENT_ID" \
        --password "$AZURE_CLIENT_SECRET" \
        --tenant "$AZURE_TENANT_ID" >/dev/null
fi

kubectl create secret generic azure-credentials \
    --from-env-file /shared/azure.env \
    --from-literal=azurestorageaccountname="$AZURE_STORAGE_ACCOUNT" \
    --from-literal=azurestorageaccountkey="$AZURE_STORAGE_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

LOGIN_JSON=$(az acr login --name "$ACR_NAME" --expose-token --output json)
ACR_USERNAME=$(echo "$LOGIN_JSON" | jq -r '.username')
ACR_PASSWORD=$(echo "$LOGIN_JSON" | jq -r '.password // .accessToken')

if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then
    echo "Failed to retrieve ACR credentials"
    exit 1
fi

kubectl create secret docker-registry registry-credentials \
    --docker-server="$ACR_LOGIN_SERVER" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

