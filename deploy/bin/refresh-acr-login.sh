#!/bin/bash

set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}

AZURE_ACR_LOGIN_SERVER=${AZURE_ACR_LOGIN_SERVER:?"AZURE_ACR_LOGIN_SERVER must be set"}
AZURE_ACR_USERNAME=${AZURE_ACR_USERNAME:?"AZURE_ACR_USERNAME must be set"}
AZURE_ACR_PASSWORD=${AZURE_ACR_PASSWORD:?"AZURE_ACR_PASSWORD must be set"}

if command -v docker >/dev/null 2>&1; then
    echo "${AZURE_ACR_PASSWORD}" | docker login \
        --username "${AZURE_ACR_USERNAME}" \
        --password-stdin \
        "${AZURE_ACR_LOGIN_SERVER}"
else
    echo "Docker is not installed. Skipping docker login." >&2
fi

$K delete --ignore-not-found secret registry-credentials
$K create secret docker-registry registry-credentials \
    --docker-server="${AZURE_ACR_LOGIN_SERVER}" \
    --docker-username="${AZURE_ACR_USERNAME}" \
    --docker-password="${AZURE_ACR_PASSWORD}"

echo "Stored Azure Container Registry credentials in secret registry-credentials"
