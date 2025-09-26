#!/bin/sh

# Part two of getting Azure credentials set up.
# This script runs in a minimal container with kubectl, and applies the credentials to the cluster.
# It reads the artifacts written by init-azure-access-retrieve.sh and creates the necessary secrets.

set -euo pipefail

TIMEOUT=60
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

if [ ! -f "$FILE" ]; then
    echo "❌ Error: File $FILE did not appear within $TIMEOUT seconds." >&2
    exit 1
fi

STORAGE_CONNECTION_STRING=$(cat /shared/storage_connection_string)
STORAGE_CONTAINER=$(cat /shared/storage_container)
ACR_LOGIN_SERVER=$(cat /shared/acr_login_server)
ACR_USERNAME=$(cat /shared/acr_username)
ACR_PASSWORD=$(cat /shared/acr_password)

echo "Creating Kubernetes secrets..."

kubectl create secret generic azure-storage \
    --from-literal=connection_string="$STORAGE_CONNECTION_STRING" \
    --from-literal=container="$STORAGE_CONTAINER" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry registry-credentials \
    --docker-server="$ACR_LOGIN_SERVER" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
