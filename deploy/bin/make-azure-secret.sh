#!/bin/bash

set -euo pipefail

fail() {
    echo "$1" >&2
    exit 1
}

K=${KUBECTL_CMD:-"kubectl"}
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$($K config view -o json | jq -r '.contexts[] | select(.name == "'$($K config current-context)'") | .context.namespace // "default"')]}
# Update K to include the deployment namespace
K="$K -n $DEPLOYMENT_NAMESPACE"

cd "$(dirname "$0")"

# Run the refresh-acr-login.sh, telling it to use the configured KUBECTL_CMD
KUBECTL_CMD="$K" ./refresh-acr-login.sh

if ! command -v az >/dev/null 2>&1; then
    fail "Azure CLI (az) is required but was not found in PATH"
fi

if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" && -n "${AZURE_TENANT_ID:-}" ]]; then
    az login \
        --service-principal \
        --username "${AZURE_CLIENT_ID}" \
        --password "${AZURE_CLIENT_SECRET}" \
        --tenant "${AZURE_TENANT_ID}" \
        >/dev/null 2>&1 || fail "Failed to login to Azure with the provided service principal"
fi

if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    az account set --subscription "${AZURE_SUBSCRIPTION_ID}" >/dev/null 2>&1 || \
        fail "Unable to set Azure subscription ${AZURE_SUBSCRIPTION_ID}"
else
    AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null || echo "")
fi

if [[ -z "${AZURE_TENANT_ID:-}" ]]; then
    AZURE_TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")
fi

if [[ -z "${AZURE_CLIENT_ID:-}" || -z "${AZURE_CLIENT_SECRET:-}" || -z "${AZURE_TENANT_ID:-}" ]]; then
    fail "AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, and AZURE_TENANT_ID must be provided to create Azure secrets"
fi

if [[ -z "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    fail "Unable to determine Azure subscription ID. Set AZURE_SUBSCRIPTION_ID or login with an account that has a default subscription."
fi

if [[ -z "${AZURE_ACR_NAME:-}" ]]; then
    AZURE_ACR_NAME=$(az acr list --query "[0].name" -o tsv 2>/dev/null || echo "")
fi

if [[ -z "${AZURE_ACR_NAME:-}" ]]; then
    fail "AZURE_ACR_NAME must be provided to create Azure secrets"
fi

AZURE_ACR_LOGIN_SERVER=${AZURE_ACR_LOGIN_SERVER:-$(az acr show --name "${AZURE_ACR_NAME}" --query loginServer -o tsv 2>/dev/null || echo "")}

$K delete --ignore-not-found secret azure-credentials
$K create secret generic azure-credentials \
    --from-literal=azure_client_id="${AZURE_CLIENT_ID}" \
    --from-literal=azure_client_secret="${AZURE_CLIENT_SECRET}" \
    --from-literal=azure_tenant_id="${AZURE_TENANT_ID}" \
    --from-literal=azure_subscription_id="${AZURE_SUBSCRIPTION_ID}" \
    --from-literal=azure_acr_name="${AZURE_ACR_NAME}" \
    --from-literal=azure_acr_login_server="${AZURE_ACR_LOGIN_SERVER}"

echo "Stored Azure credentials in secret azure-credentials"

# Optionally retrieve AWS credentials from Azure Key Vault if configured
if [[ -n "${AZURE_KEYVAULT_NAME:-}" ]]; then
    if [[ -n "${AZURE_KEYVAULT_AWS_ACCESS_KEY_ID_SECRET:-}" && -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
        AWS_ACCESS_KEY_ID=$(az keyvault secret show --vault-name "${AZURE_KEYVAULT_NAME}" --name "${AZURE_KEYVAULT_AWS_ACCESS_KEY_ID_SECRET}" --query value -o tsv 2>/dev/null || echo "")
    fi
    if [[ -n "${AZURE_KEYVAULT_AWS_SECRET_ACCESS_KEY_SECRET:-}" && -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        AWS_SECRET_ACCESS_KEY=$(az keyvault secret show --vault-name "${AZURE_KEYVAULT_NAME}" --name "${AZURE_KEYVAULT_AWS_SECRET_ACCESS_KEY_SECRET}" --query value -o tsv 2>/dev/null || echo "")
    fi
fi

# Create the AWS secret if credentials are available (for workloads that still depend on AWS)
if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    $K delete --ignore-not-found secret aws-credentials
    $K create secret generic aws-credentials \
        --from-literal=aws_access_key_id="${AWS_ACCESS_KEY_ID}" \
        --from-literal=aws_secret_access_key="${AWS_SECRET_ACCESS_KEY}"
    echo "Stored AWS credentials in secret aws-credentials"
else
    echo "AWS credentials were not provided. Skipping creation of aws-credentials secret."
fi

if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" && -n "${AZURE_TENANT_ID:-}" ]]; then
    az logout >/dev/null 2>&1 || true
fi

# Verify secrets have been properly created
if ! $K get secret registry-credentials; then
    fail "registry-credentials secret not found"
fi

if ! $K get secret azure-credentials; then
    fail "azure-credentials secret not found"
fi
