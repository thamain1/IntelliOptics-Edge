#!/bin/bash

set -euo pipefail

fail() {
    echo "$1" >&2
    exit 1
}

K=${KUBECTL_CMD:-"kubectl"}
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$($K config view -o json | jq -r '.contexts[] | select(.name == "'$($K config current-context)'") | .context.namespace // "default"')}
K="$K -n $DEPLOYMENT_NAMESPACE"

cd $(dirname "$0")

ACCOUNT_NAME=${AZURE_STORAGE_ACCOUNT_NAME:-${AZCOPY_ACCOUNT_NAME:-""}}
ACCOUNT_KEY=${AZURE_STORAGE_ACCOUNT_KEY:-${AZCOPY_ACCOUNT_KEY:-""}}

if [ -z "$ACCOUNT_NAME" ]; then
    fail "AZURE_STORAGE_ACCOUNT_NAME (or AZCOPY_ACCOUNT_NAME) environment variable not set"
fi

if [ -z "$ACCOUNT_KEY" ]; then
    fail "AZURE_STORAGE_ACCOUNT_KEY (or AZCOPY_ACCOUNT_KEY) environment variable not set"
fi

$K delete --ignore-not-found secret azure-storage-credentials
$K create secret generic azure-storage-credentials \
    --from-literal=account_name=$ACCOUNT_NAME \
    --from-literal=account_key=$ACCOUNT_KEY

if ! $K get secret azure-storage-credentials >/dev/null 2>&1; then
    fail "azure-storage-credentials secret not found after creation"
fi

