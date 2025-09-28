#!/bin/sh
set -euo pipefail

# Part two of getting registry credentials set up.
# This script runs in a minimal container with just kubectl, and applies the credentials to the cluster.
#
# We do two things:
# 1. Create a secret with an AWS credentials file. We use a file instead of environment variables
#    so that we can change it without restarting the pod.
# 2. Create (or update) a generic Docker registry credentials secret.
#
# We wait for the credentials to be written to the shared volume by the previous script.
TIMEOUT=60  # Maximum time to wait in seconds
FILE="/shared/done"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

log "Waiting up to $TIMEOUT seconds for $FILE to exist..."

i=0
while [ $i -lt $TIMEOUT ]; do
    if [ -f "$FILE" ]; then
        log "✅ File $FILE found! Continuing..."
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

REGISTRY_SECRET_NAME=${REGISTRY_SECRET_NAME:-registry-credentials}
REGISTRY_SERVER=${REGISTRY_SERVER:-${ECR_REGISTRY:-}}
CONFIG_JSON_PATH=/shared/config.json
TOKEN_PATH=/shared/token.txt

log "Creating Kubernetes secrets..."

if [ -s /shared/credentials ]; then
    kubectl create secret generic aws-credentials-file --from-file /shared/credentials \
        --dry-run=client -o yaml | kubectl apply -f -
fi

if [ -s "$CONFIG_JSON_PATH" ]; then
    kubectl create secret generic "$REGISTRY_SECRET_NAME" \
        --type=kubernetes.io/dockerconfigjson \
        --from-file=.dockerconfigjson="$CONFIG_JSON_PATH" \
        --dry-run=client -o yaml | kubectl apply -f -
elif [ -s "$TOKEN_PATH" ]; then
    # Fallback to docker-registry type if config.json is missing
    kubectl create secret docker-registry "$REGISTRY_SECRET_NAME" \
        --docker-server="$REGISTRY_SERVER" \
        --docker-username="${REGISTRY_USERNAME:-AWS}" \
        --docker-password="$(cat "$TOKEN_PATH")" \
        --dry-run=client -o yaml | kubectl apply -f -
else
    echo "❌ Neither Docker config JSON nor token file was produced. Nothing to apply." >&2
    exit 1
fi
