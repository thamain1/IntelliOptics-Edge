#!/bin/bash

set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}
REGISTRY_SECRET_NAME=${REGISTRY_SECRET_NAME:-registry-credentials}

REGISTRY_SERVER=${REGISTRY_SERVER:-}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-}
REGISTRY_PASSWORD_FILE=${REGISTRY_PASSWORD_FILE:-}
REGISTRY_EMAIL=${REGISTRY_EMAIL:-}

if [[ -z "$REGISTRY_PASSWORD" && -n "$REGISTRY_PASSWORD_FILE" ]]; then
    if [[ ! -f "$REGISTRY_PASSWORD_FILE" ]]; then
        echo "Registry password file '$REGISTRY_PASSWORD_FILE' not found" >&2
        exit 1
    fi
    REGISTRY_PASSWORD=$(<"$REGISTRY_PASSWORD_FILE")
fi

if [[ -z "$REGISTRY_SERVER" || -z "$REGISTRY_USERNAME" || -z "$REGISTRY_PASSWORD" ]]; then
    echo "REGISTRY_SERVER, REGISTRY_USERNAME, and REGISTRY_PASSWORD (or REGISTRY_PASSWORD_FILE) must be provided." >&2
    exit 1
fi

echo "Updating registry secret '$REGISTRY_SECRET_NAME' for $REGISTRY_SERVER"

if command -v docker >/dev/null 2>&1; then
    echo "$REGISTRY_PASSWORD" | docker login \
        --username "$REGISTRY_USERNAME" \
        --password-stdin \
        "$REGISTRY_SERVER"
else
    echo "Docker is not installed. Skipping local docker login."
fi

$K delete --ignore-not-found secret "$REGISTRY_SECRET_NAME"

create_args=(
    create secret docker-registry "$REGISTRY_SECRET_NAME"
    --docker-server="$REGISTRY_SERVER"
    --docker-username="$REGISTRY_USERNAME"
    --docker-password="$REGISTRY_PASSWORD"
)

if [[ -n "$REGISTRY_EMAIL" ]]; then
    create_args+=(--docker-email="$REGISTRY_EMAIL")
fi

$K "${create_args[@]}"

echo "Stored registry credentials in secret $REGISTRY_SECRET_NAME"
