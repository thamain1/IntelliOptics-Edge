#!/bin/bash

set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$($K config view -o json | jq -r '.contexts[] | select(.name == "'$($K config current-context)'") | .context.namespace // "default"')}
K="$K -n $DEPLOYMENT_NAMESPACE"

cd $(dirname "$0")

# Allow callers to provide values via environment variables. These are
# the same credentials that will later be injected into the refresh job.
AZURE_TENANT_ID=${AZURE_TENANT_ID:-${AZ_TENANT_ID:-}}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID:-${AZ_CLIENT_ID:-}}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET:-${AZ_CLIENT_SECRET:-}}
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID:-${AZ_SUBSCRIPTION_ID:-}}
AZURE_ACR_NAME=${AZURE_ACR_NAME:-${AZ_ACR_NAME:-}}
AZURE_ACR_LOGIN_SERVER=${AZURE_ACR_LOGIN_SERVER:-${AZ_ACR_LOGIN_SERVER:-}}
AZURE_ACR_USERNAME=${AZURE_ACR_USERNAME:-}
AZURE_ACR_PASSWORD=${AZURE_ACR_PASSWORD:-}

if [[ -z "${AZURE_ACR_NAME}" && -z "${AZURE_ACR_LOGIN_SERVER}" ]]; then
    echo "Either AZURE_ACR_NAME or AZURE_ACR_LOGIN_SERVER must be provided" >&2
    exit 1
fi

if [[ -z "${AZURE_CLIENT_ID}" || -z "${AZURE_CLIENT_SECRET}" ]]; then
    echo "AZURE_CLIENT_ID and AZURE_CLIENT_SECRET must be provided" >&2
    exit 1
fi

if [[ -z "${AZURE_TENANT_ID}" ]]; then
    echo "AZURE_TENANT_ID must be provided" >&2
    exit 1
fi

if [[ -z "${AZURE_ACR_LOGIN_SERVER}" ]]; then
    if command -v az >/dev/null 2>&1; then
        AZURE_ACR_LOGIN_SERVER=$(az acr show --name "${AZURE_ACR_NAME}" --query loginServer -o tsv)
    else
        AZURE_ACR_LOGIN_SERVER="${AZURE_ACR_NAME}.azurecr.io"
    fi
fi

if [[ -z "${AZURE_ACR_USERNAME}" ]]; then
    AZURE_ACR_USERNAME="${AZURE_CLIENT_ID}"
fi

if [[ -z "${AZURE_ACR_PASSWORD}" ]]; then
    AZURE_ACR_PASSWORD="${AZURE_CLIENT_SECRET}"
fi

set +x
$K delete --ignore-not-found secret azure-acr-credentials
$K create secret generic azure-acr-credentials \
    --from-literal=AZURE_TENANT_ID="${AZURE_TENANT_ID}" \
    --from-literal=AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
    --from-literal=AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}" \
    ${AZURE_SUBSCRIPTION_ID:+--from-literal=AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"} \
    --from-literal=AZURE_ACR_LOGIN_SERVER="${AZURE_ACR_LOGIN_SERVER}" \
    --from-literal=AZURE_ACR_USERNAME="${AZURE_ACR_USERNAME}" \
    --from-literal=AZURE_ACR_PASSWORD="${AZURE_ACR_PASSWORD}" \
    --from-literal=AZURE_ACR_NAME="${AZURE_ACR_NAME}"
set -x

$K delete --ignore-not-found secret registry-credentials
$K create secret docker-registry registry-credentials \
    --docker-server="${AZURE_ACR_LOGIN_SERVER}" \
    --docker-username="${AZURE_ACR_USERNAME}" \
    --docker-password="${AZURE_ACR_PASSWORD}"

if command -v docker >/dev/null 2>&1; then
    echo "${AZURE_ACR_PASSWORD}" | docker login \
        --username "${AZURE_ACR_USERNAME}" \
        --password-stdin \
        "${AZURE_ACR_LOGIN_SERVER}"
else
    echo "Docker is not installed. Skipping docker login." >&2
fi

set +x
$K get secret azure-acr-credentials >/dev/null
$K get secret registry-credentials >/dev/null
set -x

echo "Azure Container Registry credentials stored in Kubernetes secrets"
