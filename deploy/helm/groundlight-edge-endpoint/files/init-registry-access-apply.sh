#!/bin/sh

# Part two of getting registry and artifact credentials set up.
# This script runs in a minimal container with just kubectl, and applies the credentials to the cluster.

# We do two things:
# 1. Create a secret with artifact storage credentials so workloads can download models.
# 2. Create a secret with container registry credentials used to pull images.

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

ARTIFACT_ACCESS_KEY=$(sed -n 's/^access_key = //p' /shared/credentials)
ARTIFACT_SECRET_KEY=$(sed -n 's/^secret_key = //p' /shared/credentials)
ARTIFACT_ENDPOINT=$(sed -n 's/^endpoint = //p' /shared/credentials)

kubectl create secret generic artifact-storage-credentials \
    --from-literal=access_key="${ARTIFACT_ACCESS_KEY}" \
    --from-literal=secret_key="${ARTIFACT_SECRET_KEY}" \
    --from-literal=endpoint="${ARTIFACT_ENDPOINT}" \
    --dry-run=client -o yaml | kubectl apply -f -

REGISTRY_USERNAME=$(cat /shared/registry_username)
REGISTRY_PASSWORD=$(cat /shared/registry_password)

kubectl create secret docker-registry registry-credentials \
    --docker-server={{ .Values.registryHost }} \
    --docker-username="${REGISTRY_USERNAME}" \
    --docker-password="${REGISTRY_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

