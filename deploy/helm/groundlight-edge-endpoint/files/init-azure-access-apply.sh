#!/bin/sh

set -eu

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

echo "Creating Kubernetes secrets for Azure access..."

set -a
. /shared/azure-service-principal.env
set +a

kubectl create secret generic azure-service-principal \
    --from-env-file=/shared/azure-service-principal.env \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry registry-credentials \
    --docker-server="${ACR_LOGIN_SERVER:-${ACR_NAME}.azurecr.io}" \
    --docker-username="$(cat /shared/acr-username.txt)" \
    --docker-password="$(cat /shared/acr-password.txt)" \
    --dry-run=client -o yaml | kubectl apply -f -

