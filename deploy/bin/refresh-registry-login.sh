#!/bin/bash

set -e

K=${KUBECTL_CMD:-"kubectl"}
# No need to explicitly pick the namespace - this normally runs in its own namespace

REGISTRY_URL=${REGISTRY_URL:?Set REGISTRY_URL to the registry hostname}
REGISTRY_USERNAME=${REGISTRY_USERNAME:?Set REGISTRY_USERNAME for the registry}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:?Set REGISTRY_PASSWORD for the registry}

if command -v docker >/dev/null 2>&1; then
    printf '%s' "$REGISTRY_PASSWORD" | docker login \
        --username "$REGISTRY_USERNAME" \
        --password-stdin  \
        "$REGISTRY_URL"
else
    echo "Docker is not installed. Skipping registry login."
fi

$K delete --ignore-not-found secret registry-credentials

$K create secret docker-registry registry-credentials \
    --docker-server="$REGISTRY_URL" \
    --docker-username="$REGISTRY_USERNAME" \
    --docker-password="$REGISTRY_PASSWORD"

echo "Stored registry credentials in secret registry-credentials"

