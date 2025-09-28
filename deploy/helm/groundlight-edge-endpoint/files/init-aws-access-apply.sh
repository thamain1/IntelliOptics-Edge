#!/bin/bash

set -euo pipefail

# Part two of getting cloud credentials set up.
# This script runs in a minimal container with just kubectl, and applies the
# credentials to the cluster.
#
# We do two things:
# 1. Create a secret with an AWS credentials file. We use a file instead of
#    environment variables so that we can change it without restarting the pod.
# 2. Create (or update) a secret with Docker registry credentials that are
#    compatible with both AWS ECR and Azure ACR.

TIMEOUT=${TIMEOUT:-60}
MARKER_FILE="/shared/done"
REGISTRY_SECRET_NAME=${REGISTRY_SECRET_NAME:-registry-credentials}
REGISTRY_SECRET_TYPE=${REGISTRY_SECRET_TYPE:-kubernetes.io/dockerconfigjson}
REGISTRY_SERVER=${REGISTRY_SERVER:-}

log() {
  echo "[init-aws-access-apply] $*"
}

log "Waiting up to ${TIMEOUT}s for ${MARKER_FILE} to exist..."

SECONDS=0
end=$((SECONDS + TIMEOUT))
while [ $SECONDS -lt $end ]; do
  if [ -f "$MARKER_FILE" ]; then
    log "✅ Marker file found; continuing."
    break
  fi
  sleep 1
done

if [ ! -f "$MARKER_FILE" ]; then
  log "❌ Error: File ${MARKER_FILE} did not appear within ${TIMEOUT} seconds." >&2
  exit 1
fi

log "Creating Kubernetes secrets..."

kubectl create secret generic aws-credentials-file \
  --from-file /shared/credentials \
  --dry-run=client -o yaml | kubectl apply -f -

if [ ! -f /shared/dockerconfigjson ]; then
  log "❌ Expected /shared/dockerconfigjson to exist but it does not." >&2
  exit 1
fi

kubectl create secret generic "${REGISTRY_SECRET_NAME}" \
  --type "${REGISTRY_SECRET_TYPE}" \
  --from-file=.dockerconfigjson=/shared/dockerconfigjson \
  --dry-run=client -o yaml | kubectl apply -f -

if [ -n "$REGISTRY_SERVER" ]; then
  log "Updated registry credentials for ${REGISTRY_SERVER}."
else
  log "Updated registry credentials."
fi
