#!/bin/bash

set -e

K=${KUBECTL_CMD:-"kubectl"}
# No need to explicitly pick the namespace - this normally runs in its own namespace

ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-acrintellioptics.azurecr.io}
ACR_NAME=${ACR_NAME:-${ACR_LOGIN_SERVER%%.azurecr.io}}

if [ -n "$AZURE_CLIENT_ID" ] && [ -n "$AZURE_CLIENT_SECRET" ] && [ -n "$AZURE_TENANT_ID" ]; then
    echo "Logging in to Azure with the provided service principal"
    az account show >/dev/null 2>&1 || \
        az login --service-principal \
            --username "$AZURE_CLIENT_ID" \
            --password "$AZURE_CLIENT_SECRET" \
            --tenant "$AZURE_TENANT_ID" >/dev/null
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not found; installing via az aks install-cli"
    az aks install-cli >/dev/null
fi

LOGIN_JSON=$(az acr login --name ${ACR_NAME} --expose-token --output json)
if [ $? -ne 0 ]; then
    echo "Failed to fetch ACR login token"
    exit 1
fi

ACR_USERNAME=$(echo "$LOGIN_JSON" | jq -r '.username')
ACR_PASSWORD=$(echo "$LOGIN_JSON" | jq -r '.password // .accessToken')

if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then
    echo "Failed to parse ACR credentials"
    exit 1
fi

echo "Fetched short-lived ACR credentials from Azure"

if command -v docker >/dev/null 2>&1; then
    echo $ACR_PASSWORD | docker login \
        --username $ACR_USERNAME \
        --password-stdin  \
        $ACR_LOGIN_SERVER
else
    echo "Docker is not installed. Skipping docker ACR login."
fi

$K delete --ignore-not-found secret registry-credentials

$K create secret docker-registry registry-credentials \
    --docker-server=$ACR_LOGIN_SERVER \
    --docker-username=$ACR_USERNAME \
    --docker-password=$ACR_PASSWORD

echo "Stored ACR credentials in secret registry-credentials"

