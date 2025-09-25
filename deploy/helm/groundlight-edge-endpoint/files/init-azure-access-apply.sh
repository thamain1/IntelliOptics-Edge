#!/bin/sh

set -eu

# Part two of getting Azure registry credentials set up.
# This script runs in a minimal container with just kubectl, and applies the credentials to the cluster.
#
# We do one thing:
# 1. Create or update a secret with Docker registry credentials. This is used to pull images from ACR.
#
# We wait for the credentials to be written to the shared volume by the previous script.
TIMEOUT=60  # Maximum time to wait in seconds
FILE="/shared/done"

echo "Waiting up to $TIMEOUT seconds for $FILE to exist..."

i=0
while [ $i -lt $TIMEOUT ]; do
    if [ -f "$FILE" ]; then
        echo "✅ File $FILE found! Continuing..."
        break
    fi
    sleep 1
    i=$((i + 1))
done

# If the loop completed without breaking, the file did not appear
if [ ! -f "$FILE" ]; then
    echo "❌ Error: File $FILE did not appear within $TIMEOUT seconds." >&2
    exit 1
fi

if [ ! -f /shared/registry.env ]; then
    echo "❌ Error: /shared/registry.env does not exist." >&2
    exit 1
fi

. /shared/registry.env

if [ -z "${AZURE_REGISTRY:-}" ] || [ -z "${AZURE_REGISTRY_USERNAME:-}" ] || [ -z "${AZURE_REGISTRY_PASSWORD:-}" ]; then
    echo "❌ Error: Missing Azure registry credentials." >&2
    exit 1
fi

kubectl create secret docker-registry acr-credentials \
    --docker-server="${AZURE_REGISTRY}" \
    --docker-username="${AZURE_REGISTRY_USERNAME}" \
    --docker-password="${AZURE_REGISTRY_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -
