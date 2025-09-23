#!/bin/bash

set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$($K config view -o json | jq -r '.contexts[] | select(.name == "'$($K config current-context)'") | .context.namespace // "default"')}
# Update K to include the deployment namespace
K="$K -n $DEPLOYMENT_NAMESPACE"

cd $(dirname "$0")

# Run the refresh-ecr-login.sh, telling it to use the configured KUBECTL_CMD
KUBECTL_CMD="$K" ./refresh-ecr-login.sh

# Collect Azure credential environment variables so they can be stored in a secret
SECRET_NAME=${AZURE_REGISTRY_AUTH_SECRET_NAME:-azure-registry-auth}
SECRET_ARGS=()

add_secret_literal() {
    local key="$1"
    local value="$2"
    if [[ -n "$value" ]]; then
        SECRET_ARGS+=("--from-literal=${key}=${value}")
    fi
}

add_secret_literal "AZURE_CLIENT_ID" "${AZURE_CLIENT_ID:-}"
add_secret_literal "AZURE_CLIENT_SECRET" "${AZURE_CLIENT_SECRET:-}"
add_secret_literal "AZURE_TENANT_ID" "${AZURE_TENANT_ID:-}"
add_secret_literal "AZURE_USE_MANAGED_IDENTITY" "${AZURE_USE_MANAGED_IDENTITY:-}"
add_secret_literal "IDENTITY_CLIENT_ID" "${IDENTITY_CLIENT_ID:-}"
add_secret_literal "ACR_USERNAME" "${ACR_USERNAME:-}"
add_secret_literal "ACR_PASSWORD" "${ACR_PASSWORD:-}"
add_secret_literal "ACR_LOGIN_SERVER" "${ACR_LOGIN_SERVER:-}"
add_secret_literal "ACR_NAME" "${ACR_NAME:-}"

if [[ ${#SECRET_ARGS[@]} -gt 0 ]]; then
    echo "Storing Azure registry authentication settings in secret ${SECRET_NAME}"
    $K delete --ignore-not-found secret "$SECRET_NAME" >/dev/null 2>&1 || true
    $K create secret generic "$SECRET_NAME" \
        ${SECRET_ARGS[@]}
else
    echo "No Azure registry authentication environment variables provided; skipping creation of ${SECRET_NAME} secret."
fi

# Verify that the registry-credentials secret exists
if ! $K get secret registry-credentials >/dev/null 2>&1; then
    echo "registry-credentials secret not found"
    exit 1
fi
