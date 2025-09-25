#!/bin/bash

set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}

if ! command -v az >/dev/null 2>&1; then
    echo "The Azure CLI (az) is required but not installed or not on PATH." >&2
    exit 1
fi

ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-}
ACR_NAME=${ACR_NAME:-}

if [[ -z "${ACR_LOGIN_SERVER}" && -n "${ACR_NAME}" ]]; then
    ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
fi

if [[ -z "${ACR_NAME}" && -n "${ACR_LOGIN_SERVER}" ]]; then
    ACR_NAME="${ACR_LOGIN_SERVER%%.*}"
fi

if [[ -z "${ACR_NAME}" ]]; then
    echo "ACR_NAME or ACR_LOGIN_SERVER must be provided." >&2
    exit 1
fi

if [[ -z "${ACR_LOGIN_SERVER}" ]]; then
    ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
fi

# Authenticate with Azure if needed
if ! az account show >/dev/null 2>&1; then
    if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_TENANT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" ]]; then
        echo "Logging into Azure using the provided service principal." >&2
        az login --service-principal \
            --username "${AZURE_CLIENT_ID}" \
            --password "${AZURE_CLIENT_SECRET}" \
            --tenant "${AZURE_TENANT_ID}" \
            >/dev/null
    else
        echo "Azure CLI is not logged in and service principal credentials were not provided." >&2
        exit 1
    fi
fi

# Ensure we can access the registry. This also validates permissions.
az acr login --name "${ACR_NAME}" >/dev/null

read -r ACR_USERNAME ACR_PASSWORD < <(az acr credential show \
    --name "${ACR_NAME}" \
    --query "[username,passwords[0].value]" \
    -o tsv)

if [[ -z "${ACR_USERNAME}" || -z "${ACR_PASSWORD}" ]]; then
    echo "Failed to retrieve ACR credentials." >&2
    exit 1
fi

echo "Fetched admin credentials for ${ACR_LOGIN_SERVER}."

if command -v docker >/dev/null 2>&1; then
    echo "Logging docker into ${ACR_LOGIN_SERVER}."
    echo "${ACR_PASSWORD}" | docker login \
        --username "${ACR_USERNAME}" \
        --password-stdin \
        "${ACR_LOGIN_SERVER}"
else
    echo "Docker is not installed. Skipping docker ACR login." >&2
fi

${K} delete --ignore-not-found secret registry-credentials

${K} create secret docker-registry registry-credentials \
    --docker-server="${ACR_LOGIN_SERVER}" \
    --docker-username="${ACR_USERNAME}" \
    --docker-password="${ACR_PASSWORD}"

echo "Stored ACR credentials in secret registry-credentials"
