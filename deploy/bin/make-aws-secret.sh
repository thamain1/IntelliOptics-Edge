#!/bin/bash

# Provision Azure credentials and ensure the registry pull secret is present.

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

# Run the refresh-ecr-login.sh (now Azure aware), telling it to use the configured KUBECTL_CMD
KUBECTL_CMD="$K" ./refresh-ecr-login.sh

ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-acrintellioptics.azurecr.io}
ACR_NAME=${ACR_NAME:-${ACR_LOGIN_SERVER%%.azurecr.io}}

REQUIRED_VARS=(
  AZURE_CLIENT_ID
  AZURE_CLIENT_SECRET
  AZURE_TENANT_ID
  AZURE_STORAGE_ACCOUNT
  AZURE_STORAGE_KEY
  AZURE_STORAGE_CONTAINER
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        fail "Environment variable $var must be set to create Azure secrets"
    fi
done


$K delete --ignore-not-found secret azure-credentials

args=(
  --from-literal=AZURE_CLIENT_ID="${AZURE_CLIENT_ID}"
  --from-literal=AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}"
  --from-literal=AZURE_TENANT_ID="${AZURE_TENANT_ID}"
  --from-literal=AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT}"
  --from-literal=AZURE_STORAGE_KEY="${AZURE_STORAGE_KEY}"
  --from-literal=AZURE_STORAGE_CONTAINER="${AZURE_STORAGE_CONTAINER}"
  --from-literal=ACR_LOGIN_SERVER="${ACR_LOGIN_SERVER}"
  --from-literal=ACR_NAME="${ACR_NAME}"
  --from-literal=azurestorageaccountname="${AZURE_STORAGE_ACCOUNT}"
  --from-literal=azurestorageaccountkey="${AZURE_STORAGE_KEY}"
)

if [ -n "${AZURE_SUBSCRIPTION_ID:-}" ]; then
    args+=(--from-literal=AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}")
fi

$K create secret generic azure-credentials "${args[@]}"

# Verify secrets have been properly created
if ! $K get secret registry-credentials; then
    # These should have been created in refresh-ecr-login.sh
    fail "registry-credentials secret not found"
fi

if ! $K get secret azure-credentials; then
    echo "azure-credentials secret not found"
fi

