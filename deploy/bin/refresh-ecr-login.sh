#!/bin/bash

set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}

ACR_NAME="acrintellioptics"
ACR_SERVER="${ACR_NAME}.azurecr.io"

required_env_vars=(
  "AZURE_CLIENT_ID"
  "AZURE_CLIENT_SECRET"
  "AZURE_TENANT_ID"
)

for var in "${required_env_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "Environment variable $var is required but not set"
    exit 1
  fi
done

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI (az) is not installed. Cannot continue."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to parse Azure CLI output."
  exit 1
fi

echo "Logging in to Azure container registry"
az login --service-principal \
  --username "$AZURE_CLIENT_ID" \
  --password "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID" \
  --output none

token_json=$(az acr login --name "$ACR_NAME" --expose-token --output json)
if [ -z "$token_json" ]; then
  echo "Failed to fetch ACR token from Azure"
  exit 1
fi

acr_username=$(printf '%s' "$token_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data["username"])')
acr_password=$(printf '%s' "$token_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data["passwords"][0]["value"])')

if [ -z "$acr_username" ] || [ -z "$acr_password" ]; then
  echo "Failed to parse ACR credentials from Azure response"
  exit 1
fi

echo "Fetched short-lived ACR credentials from Azure"

if command -v docker >/dev/null 2>&1; then
  printf '%s' "$acr_password" | docker login \
    --username "$acr_username" \
    --password-stdin \
    "$ACR_SERVER"
else
  echo "Docker is not installed. Skipping docker ACR login."
fi

$K delete --ignore-not-found secret registry-credentials

$K create secret docker-registry registry-credentials \
  --docker-server="$ACR_SERVER" \
  --docker-username="$acr_username" \
  --docker-password="$acr_password"

echo "Stored ACR credentials in secret registry-credentials"
