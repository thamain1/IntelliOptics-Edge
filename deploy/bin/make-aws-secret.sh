#!/bin/bash

set -euo pipefail

fail() {
    echo "$1" >&2
    exit 1
}

K=${KUBECTL_CMD:-"kubectl"}
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$($K config view -o json | jq -r '.contexts[] | select(.name == "'$($K config current-context)'") | .context.namespace // "default"')}
K="$K -n $DEPLOYMENT_NAMESPACE"

REGISTRY_SECRET_NAME=${REGISTRY_SECRET_NAME:-registry-credentials}
REGISTRY_SERVER=${REGISTRY_SERVER:-}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-}
REGISTRY_PASSWORD_FILE=${REGISTRY_PASSWORD_FILE:-}
REGISTRY_EMAIL=${REGISTRY_EMAIL:-}

if [[ -z "$REGISTRY_PASSWORD" && -n "$REGISTRY_PASSWORD_FILE" ]]; then
    if [[ ! -f "$REGISTRY_PASSWORD_FILE" ]]; then
        fail "Registry password file '$REGISTRY_PASSWORD_FILE' not found"
    fi
    REGISTRY_PASSWORD=$(<"$REGISTRY_PASSWORD_FILE")
fi

if [[ -z "$REGISTRY_SERVER" || -z "$REGISTRY_USERNAME" || -z "$REGISTRY_PASSWORD" ]]; then
    fail "REGISTRY_SERVER, REGISTRY_USERNAME, and REGISTRY_PASSWORD (or REGISTRY_PASSWORD_FILE) must be provided"
fi

cd $(dirname "$0")

KUBECTL_CMD="$K" \
REGISTRY_SECRET_NAME="$REGISTRY_SECRET_NAME" \
REGISTRY_SERVER="$REGISTRY_SERVER" \
REGISTRY_USERNAME="$REGISTRY_USERNAME" \
REGISTRY_PASSWORD="$REGISTRY_PASSWORD" \
REGISTRY_EMAIL="$REGISTRY_EMAIL" \
./refresh-ecr-login.sh

MODEL_SYNC_SECRET_NAME=${MODEL_SYNC_SECRET_NAME:-object-store-credentials}
MODEL_SYNC_CREDENTIALS_FILE=${MODEL_SYNC_CREDENTIALS_FILE:-}

if [[ -z "$MODEL_SYNC_CREDENTIALS_FILE" ]]; then
    DEFAULT_MODEL_FILE="$HOME/.aws/credentials"
    if [[ -f "$DEFAULT_MODEL_FILE" ]]; then
        MODEL_SYNC_CREDENTIALS_FILE="$DEFAULT_MODEL_FILE"
    fi
fi

if [[ -n "$MODEL_SYNC_CREDENTIALS_FILE" ]]; then
    if [[ ! -f "$MODEL_SYNC_CREDENTIALS_FILE" ]]; then
        echo "Model sync credentials file '$MODEL_SYNC_CREDENTIALS_FILE' not found; skipping secret creation." >&2
    else
        echo "Creating secret '$MODEL_SYNC_SECRET_NAME' from $MODEL_SYNC_CREDENTIALS_FILE"
        $K delete --ignore-not-found secret "$MODEL_SYNC_SECRET_NAME"
        $K create secret generic "$MODEL_SYNC_SECRET_NAME" \
            --from-file=credentials="$MODEL_SYNC_CREDENTIALS_FILE"
    fi
else
    echo "MODEL_SYNC_CREDENTIALS_FILE not provided and default credentials file not found; skipping object storage secret creation."
fi

$K get secret "$REGISTRY_SECRET_NAME" >/dev/null

if ! $K get secret "$MODEL_SYNC_SECRET_NAME" >/dev/null 2>&1; then
    echo "Warning: secret '$MODEL_SYNC_SECRET_NAME' not found. Inference model sync may fail if credentials are required." >&2
fi
