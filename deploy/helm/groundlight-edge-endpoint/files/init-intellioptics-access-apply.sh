#!/bin/sh

# Part two of getting registry credentials set up.
# This script runs in a minimal container with just kubectl, and applies the credentials to the cluster.

# We create or update a docker-registry secret that Kubernetes will use when pulling
# images from the IntelliOptics Azure Container Registry.

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


echo "Creating Kubernetes secrets..."

if [ ! -f /shared/registry.env ]; then
    echo "❌ Error: /shared/registry.env not found." >&2
    exit 1
fi

. /shared/registry.env

if [ -z "$REGISTRY_LOGIN_SERVER" ] || [ -z "$REGISTRY_USERNAME" ] || [ -z "$REGISTRY_PASSWORD" ]; then
    echo "❌ Error: registry credentials are incomplete." >&2
    exit 1
fi

kubectl create secret docker-registry registry-credentials \
    --docker-server="${REGISTRY_LOGIN_SERVER}" \
    --docker-username="${REGISTRY_USERNAME}" \
    --docker-password="${REGISTRY_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

