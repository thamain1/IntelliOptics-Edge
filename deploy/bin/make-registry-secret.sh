#!/bin/bash

set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}

fail() {
    echo "$1" >&2
    exit 1
}

AZURE_CLIENT_ID=${AZURE_CLIENT_ID:-}
AZURE_TENANT_ID=${AZURE_TENANT_ID:-}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET:-}

if [[ -z "${AZURE_CLIENT_ID}" || -z "${AZURE_TENANT_ID}" || -z "${AZURE_CLIENT_SECRET}" ]]; then
    fail "AZURE_CLIENT_ID, AZURE_TENANT_ID, and AZURE_CLIENT_SECRET must be set to create the registry credentials."
fi

ACR_NAME=${ACR_NAME:-acrintellioptics}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-${ACR_NAME}.azurecr.io}

KUBECTL_CMD="$K" ACR_NAME="$ACR_NAME" ACR_LOGIN_SERVER="$ACR_LOGIN_SERVER" \
    AZURE_CLIENT_ID="$AZURE_CLIENT_ID" AZURE_TENANT_ID="$AZURE_TENANT_ID" \
    AZURE_CLIENT_SECRET="$AZURE_CLIENT_SECRET" \
    ./refresh-ecr-login.sh

${K} delete --ignore-not-found secret azure-service-principal
${K} create secret generic azure-service-principal \
    --from-literal=clientId="${AZURE_CLIENT_ID}" \
    --from-literal=tenantId="${AZURE_TENANT_ID}" \
    --from-literal=clientSecret="${AZURE_CLIENT_SECRET}"

if ! ${K} get secret registry-credentials >/dev/null 2>&1; then
    fail "registry-credentials secret not found"
fi

if ! ${K} get secret azure-service-principal >/dev/null 2>&1; then
    fail "azure-service-principal secret not found"
fi

echo "Azure registry credentials configured successfully."
