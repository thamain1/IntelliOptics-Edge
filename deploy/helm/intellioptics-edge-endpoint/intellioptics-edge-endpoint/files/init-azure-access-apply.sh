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

SHARED_DIR="/shared"
AZURE_ENV_FILE="$SHARED_DIR/azure-service-principal.env"
ACR_USERNAME_FILE="$SHARED_DIR/acr-username.txt"
ACR_PASSWORD_FILE="$SHARED_DIR/acr-password.txt"

fail() {
    echo "❌ Error: $*" >&2
    exit 1
}

require_file() {
    file_path="$1"
    description="$2"

    if [ ! -f "$file_path" ]; then
        fail "$description ($file_path) is missing."
    fi

    if [ ! -s "$file_path" ]; then
        fail "$description ($file_path) is empty."
    fi
}

require_var() {
    var_name="$1"
    eval "value=\"\${$var_name:-}\""
    if [ -z "$value" ]; then
        fail "$var_name must be set in $AZURE_ENV_FILE."
    fi
}

echo "Creating Kubernetes secrets for Azure access..."

require_file "$AZURE_ENV_FILE" "Azure service principal environment file"

set -a
. "$AZURE_ENV_FILE"
set +a

require_var "AZURE_CLIENT_ID"
require_var "AZURE_CLIENT_SECRET"
require_var "AZURE_TENANT_ID"

registry_server="${ACR_LOGIN_SERVER:-}"

if [ -z "$registry_server" ]; then
    fail "ACR_LOGIN_SERVER must be set in $AZURE_ENV_FILE."
fi

if printf '%s' "$registry_server" | grep -q 'amazonaws.com'; then
    fail "Registry server $registry_server appears to be AWS ECR, which is not supported in this script."
fi

require_file "$ACR_USERNAME_FILE" "Azure Container Registry username artifact"
require_file "$ACR_PASSWORD_FILE" "Azure Container Registry password artifact"

ACR_USERNAME="$(cat "$ACR_USERNAME_FILE")"
ACR_PASSWORD="$(cat "$ACR_PASSWORD_FILE")"

if [ -z "$ACR_USERNAME" ]; then
    fail "Azure Container Registry username is empty."
fi

if [ -z "$ACR_PASSWORD" ]; then
    fail "Azure Container Registry password is empty."
fi

kubectl create secret generic azure-service-principal \
    --from-env-file="$AZURE_ENV_FILE" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry registry-credentials \
    --docker-server="$registry_server" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

