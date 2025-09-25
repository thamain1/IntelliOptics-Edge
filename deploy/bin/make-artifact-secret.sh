#!/bin/bash

K=${KUBECTL_CMD:-"kubectl"}
DEPLOYMENT_NAMESPACE=${DEPLOYMENT_NAMESPACE:-$($K config view -o json | jq -r '.contexts[] | select(.name == "'$($K config current-context)'") | .context.namespace // "default"')}
# Update K to include the deployment namespace
K="$K -n $DEPLOYMENT_NAMESPACE"

cd $(dirname "$0")

# Run the refresh-registry-login.sh, telling it to use the configured KUBECTL_CMD
KUBECTL_CMD="$K" ./refresh-registry-login.sh

ARTIFACT_STORAGE_ACCESS_KEY=${ARTIFACT_STORAGE_ACCESS_KEY:?Set ARTIFACT_STORAGE_ACCESS_KEY for object storage access}
ARTIFACT_STORAGE_SECRET_KEY=${ARTIFACT_STORAGE_SECRET_KEY:?Set ARTIFACT_STORAGE_SECRET_KEY for object storage access}
ARTIFACT_STORAGE_ENDPOINT=${ARTIFACT_STORAGE_ENDPOINT:-}

$K delete --ignore-not-found secret artifact-storage-credentials

CREATE_ARGS=(
    --from-literal=access_key="${ARTIFACT_STORAGE_ACCESS_KEY}"
    --from-literal=secret_key="${ARTIFACT_STORAGE_SECRET_KEY}"
)

if [ -n "$ARTIFACT_STORAGE_ENDPOINT" ]; then
    CREATE_ARGS+=(--from-literal=endpoint="${ARTIFACT_STORAGE_ENDPOINT}")
fi

$K create secret generic artifact-storage-credentials "${CREATE_ARGS[@]}"

# Verify secrets have been properly created
if ! $K get secret registry-credentials >/dev/null 2>&1; then
    # These should have been created in refresh-registry-login.sh
    echo "registry-credentials secret not found" >&2
    exit 1
fi

if ! $K get secret artifact-storage-credentials >/dev/null 2>&1; then
    echo "artifact-storage-credentials secret not found"
fi

