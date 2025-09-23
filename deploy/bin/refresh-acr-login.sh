#!/bin/bash

set -euo pipefail

fail() {
    echo "${1}" >&2
    exit 1
}

K=${KUBECTL_CMD:-"kubectl"}
# No need to explicitly pick the namespace - this normally runs in its own namespace

AZURE_ACR_NAME=${AZURE_ACR_NAME:-${ACR_NAME:-}}
AZURE_ACR_LOGIN_SERVER=${AZURE_ACR_LOGIN_SERVER:-${ACR_LOGIN_SERVER:-}}
AZURE_ACR_USERNAME=${AZURE_ACR_USERNAME:-${ACR_USERNAME:-}}
AZURE_ACR_PASSWORD=${AZURE_ACR_PASSWORD:-${ACR_PASSWORD:-}}

if ! command -v az >/dev/null 2>&1; then
    fail "Azure CLI (az) is required but was not found in PATH"
fi

login_performed=false
if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" && -n "${AZURE_TENANT_ID:-}" ]]; then
    az login \
        --service-principal \
        --username "${AZURE_CLIENT_ID}" \
        --password "${AZURE_CLIENT_SECRET}" \
        --tenant "${AZURE_TENANT_ID}" \
        >/dev/null 2>&1 || fail "Failed to login to Azure with the provided service principal"
    login_performed=true
fi

if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    az account set --subscription "${AZURE_SUBSCRIPTION_ID}" >/dev/null 2>&1 || \
        fail "Unable to set Azure subscription ${AZURE_SUBSCRIPTION_ID}"
elif $login_performed; then
    AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null || true)
fi

if [[ -z "${AZURE_ACR_NAME}" ]]; then
    fail "AZURE_ACR_NAME is required to refresh Azure Container Registry credentials"
fi

if [[ -z "${AZURE_ACR_LOGIN_SERVER}" ]]; then
    AZURE_ACR_LOGIN_SERVER=$(az acr show --name "${AZURE_ACR_NAME}" --query loginServer -o tsv 2>/dev/null || true)
fi

if [[ -z "${AZURE_ACR_LOGIN_SERVER}" ]]; then
    fail "Unable to determine Azure Container Registry login server"
fi

if [[ -z "${AZURE_ACR_USERNAME}" ]]; then
    AZURE_ACR_USERNAME=$(az acr credential show --name "${AZURE_ACR_NAME}" --query "username" -o tsv 2>/dev/null || true)
fi

if [[ -z "${AZURE_ACR_PASSWORD}" ]]; then
    AZURE_ACR_PASSWORD=$(az acr credential show --name "${AZURE_ACR_NAME}" --query "passwords[0].value" -o tsv 2>/dev/null || true)
fi

if [[ -z "${AZURE_ACR_USERNAME}" || -z "${AZURE_ACR_PASSWORD}" ]]; then
    fail "Failed to resolve Azure Container Registry credentials. Ensure the admin user is enabled or provide AZURE_ACR_USERNAME/AZURE_ACR_PASSWORD."
fi

echo "Fetched short-lived ACR credentials from Azure"

if command -v docker >/dev/null 2>&1; then
    echo "${AZURE_ACR_PASSWORD}" | docker login \
        --username "${AZURE_ACR_USERNAME}" \
        --password-stdin \
        "${AZURE_ACR_LOGIN_SERVER}"
else
    echo "Docker is not installed. Skipping docker ACR login."
fi

$K delete --ignore-not-found secret registry-credentials

$K create secret docker-registry registry-credentials \
    --docker-server="${AZURE_ACR_LOGIN_SERVER}" \
    --docker-username="${AZURE_ACR_USERNAME}" \
    --docker-password="${AZURE_ACR_PASSWORD}"

if $login_performed; then
    az logout >/dev/null 2>&1 || true
fi

echo "Stored ACR credentials in secret registry-credentials"
