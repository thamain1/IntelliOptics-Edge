#!/bin/sh

# Part two of setting up container registry access for the edge endpoint.
# This script runs in a minimal container with kubectl, waits for the
# credentials to be written to the shared volume by init-aws-access-retrieve.sh,
# and then creates/updates the registry-credentials secret in Kubernetes.

set -eu

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
    echo "❌ Error: Registry credentials were not written to /shared/registry.env" >&2
    exit 1
fi

set -a
. /shared/registry.env
set +a

if [ -z "${ACR_LOGIN_SERVER:-}" ] || [ -z "${ACR_USERNAME:-}" ] || [ -z "${ACR_PASSWORD:-}" ]; then
    echo "❌ Error: Missing required registry credential fields." >&2
    exit 1
fi

echo "Creating Kubernetes secret registry-credentials..."

kubectl create secret docker-registry registry-credentials \
    --docker-server="${ACR_LOGIN_SERVER}" \
    --docker-username="${ACR_USERNAME}" \
    --docker-password="${ACR_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -
