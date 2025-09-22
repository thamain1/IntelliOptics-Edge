#!/bin/bash

fail() {
    echo "$1" >&2
    exit 1
}

K=${KUBECTL_CMD:-"kubectl"}
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$($K config view -o json | jq -r '.contexts[] | select(.name == "'$($K config current-context)'") | .context.namespace // "default"')}
# Update K to include the deployment namespace
K="$K -n $DEPLOYMENT_NAMESPACE"

cd $(dirname "$0")

# Run the refresh-acr-login.sh, telling it to use the configured KUBECTL_CMD
KUBECTL_CMD="$K" ./refresh-acr-login.sh

# Gather Azure registry credentials from environment variables
AZURE_REGISTRY_USERNAME=${AZURE_REGISTRY_USERNAME:?"AZURE_REGISTRY_USERNAME must be set"}
AZURE_REGISTRY_PASSWORD=${AZURE_REGISTRY_PASSWORD:?"AZURE_REGISTRY_PASSWORD must be set"}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:?"ACR_LOGIN_SERVER must be set"}

# Create or update the secret with registry credentials
$K delete --ignore-not-found secret azure-registry-credentials
$K create secret generic azure-registry-credentials \
    --from-literal=azure_registry_username=$AZURE_REGISTRY_USERNAME \
    --from-literal=azure_registry_password=$AZURE_REGISTRY_PASSWORD \
    --from-literal=acr_login_server=$ACR_LOGIN_SERVER

# Verify secrets have been properly created
if ! $K get secret registry-credentials; then
    # These should have been created in refresh-acr-login.sh
    fail "registry-credentials secret not found"
fi

if ! $K get secret azure-registry-credentials; then
    echo "azure-registry-credentials secret not found"
fi

