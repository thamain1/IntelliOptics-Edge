#!/bin/sh

set -euo pipefail

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

if [ -z "${AZURE_ACR_LOGIN_SERVER:-}" ]; then
  echo "AZURE_ACR_LOGIN_SERVER must be provided" >&2
  exit 1
fi

if [ -z "${AZURE_ACR_USERNAME:-}" ]; then
  echo "AZURE_ACR_USERNAME must be provided" >&2
  exit 1
fi

echo "Creating Kubernetes secrets..."

kubectl create secret generic azure-acr-credentials-file --from-file /shared/credentials \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry registry-credentials \
    --docker-server="${AZURE_ACR_LOGIN_SERVER}" \
    --docker-username="${AZURE_ACR_USERNAME}" \
    --docker-password="$(cat /shared/token.txt)" \
    --dry-run=client -o yaml | kubectl apply -f -
