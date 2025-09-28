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
ACR_NAME=${ACR_NAME:-"acrintellioptics"}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-"${ACR_NAME}.azurecr.io"}

if ! command -v az >/dev/null 2>&1; then
    echo "Azure CLI (az) is required to refresh registry credentials." >&2
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

if ! az account show >/dev/null 2>&1; then
    if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_TENANT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" ]]; then
        echo "Logging in to Azure with the provided service principal credentials"
        az login --service-principal \
            --username "$AZURE_CLIENT_ID" \
            --password "$AZURE_CLIENT_SECRET" \
            --tenant "$AZURE_TENANT_ID" >/dev/null
    else
        echo "Azure CLI is not logged in and service principal credentials were not provided." >&2
        exit 1
    fi
fi

echo "Fetching Azure Container Registry credentials from $ACR_NAME"
ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query "username" -o tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv)

if [[ -z "$ACR_USERNAME" || -z "$ACR_PASSWORD" ]]; then
    echo "Failed to retrieve credentials for Azure Container Registry $ACR_NAME" >&2
    exit 1
fi

if command -v docker >/dev/null 2>&1; then
    echo "Logging docker into $ACR_LOGIN_SERVER"
    echo "$ACR_PASSWORD" | docker login \
        --username "$ACR_USERNAME" \
        --password-stdin \
        "$ACR_LOGIN_SERVER"
else
    echo "Docker is not installed. Skipping docker login." >&2
fi

echo "Updating registry-credentials secret with Azure Container Registry credentials"
$K delete --ignore-not-found secret registry-credentials
$K create secret docker-registry registry-credentials \

  --docker-server="$ACR_SERVER" \
  --docker-username="$acr_username" \
  --docker-password="$acr_password"

    --docker-server="$ACR_LOGIN_SERVER" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD"

echo "Stored Azure Container Registry credentials in secret registry-credentials"


echo "Stored ACR credentials in secret registry-credentials"
