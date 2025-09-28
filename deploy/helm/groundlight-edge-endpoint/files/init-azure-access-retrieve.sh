#!/bin/bash

set -euo pipefail

ACR_NAME="${ACR_NAME:-acrintellioptics}"
ACR_LOGIN_SERVER="${ACR_LOGIN_SERVER:-${ACR_NAME}.azurecr.io}"

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI (az) is required to retrieve registry credentials" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for parsing credential responses" >&2
  exit 1
fi

if [ "${1:-}" = "validate" ]; then
  echo "Validating INTELLIOPTICS_API_TOKEN and INTELLIOPTICS_ENDPOINT..."
  if [ -z "${INTELLIOPTICS_API_TOKEN:-}" ]; then
    echo "INTELLIOPTICS_API_TOKEN is not set. Exiting."
    exit 1
  fi

  if [ -z "${INTELLIOPTICS_ENDPOINT:-}" ]; then
    echo "INTELLIOPTICS_ENDPOINT is not set. Exiting."
    exit 1
  fi
  validate="yes"
fi

sanitize_endpoint_url() {
    local endpoint="${1:-$INTELLIOPTICS_ENDPOINT}"

    if [[ -z "$endpoint" ]]; then
        endpoint="https://intellioptics-api-37558.azurewebsites.net/"
    fi

    if [[ "$endpoint" =~ ^(https?)://([^/]+)(/.*)?$ ]]; then
        scheme="${BASH_REMATCH[1]}"
        netloc="${BASH_REMATCH[2]}"
        path="${BASH_REMATCH[3]}"
    else
        echo "Invalid API endpoint: $endpoint. Must be a valid URL with http or https scheme." >&2
        exit 1
    fi

    if [[ -z "$path" ]]; then
        path="/"
    fi

    if [[ "${path: -1}" != "/" ]]; then
        path="$path/"
    fi

    if [[ "$path" == "/" ]]; then
        path="/device-api/"
    fi

    case "$path" in
        "/device-api/"|"/v1/"|"/v2/"|"/v3/")
            ;;
        *)
            echo "Warning: Configured endpoint $endpoint does not look right - path '$path' seems wrong." >&2
            ;;
    esac

    sanitized_endpoint="${scheme}://${netloc}${path%/}"
    echo "$sanitized_endpoint"
}

sanitized_url=$(sanitize_endpoint_url "${INTELLIOPTICS_ENDPOINT}")
echo "Sanitized URL: $sanitized_url"

echo "Fetching Azure service principal credentials from the IntelliOptics cloud service..."
HTTP_STATUS=$(curl -s -L -o /tmp/credentials.json -w "%{http_code}" --fail-with-body --header "x-api-token: ${INTELLIOPTICS_API_TOKEN}" ${sanitized_url}/reader-credentials)

if [ $? -ne 0 ]; then
  echo "Failed to fetch credentials from the IntelliOptics cloud service"
  if [ -n "$HTTP_STATUS" ]; then
    echo "HTTP Status: $HTTP_STATUS"
  fi
  echo -n "Response: "
  cat /tmp/credentials.json; echo
  exit 1
fi

if [ "${validate:-}" = "yes" ]; then
  echo "API token validation successful. Exiting."
  exit 0
fi

mapfile -t azure_fields < <(python3 <<'PY'
import json
from pathlib import Path

data = json.loads(Path("/tmp/credentials.json").read_text())

def get(key, default=""):
    value = data.get(key, default)
    return value if value is not None else default

print(get("azure_client_id"))
print(get("azure_client_secret"))
print(get("azure_tenant_id"))
print(get("acr_name", "acrintellioptics"))
print(get("acr_login_server"))
print(get("azure_storage_connection_string"))
PY
)

AZURE_CLIENT_ID="${azure_fields[0]}"
AZURE_CLIENT_SECRET="${azure_fields[1]}"
AZURE_TENANT_ID="${azure_fields[2]}"
ACR_NAME="${azure_fields[3]}"
ACR_LOGIN_SERVER="${azure_fields[4]}"
AZURE_STORAGE_CONNECTION_STRING="${azure_fields[5]}"

if [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_CLIENT_SECRET" ] || [ -z "$AZURE_TENANT_ID" ]; then
    echo "Azure service principal credentials missing from response" >&2
    exit 1
fi

if [ -z "$ACR_NAME" ]; then
    ACR_NAME="acrintellioptics"
fi

if [ -z "$ACR_LOGIN_SERVER" ]; then
    ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
fi

az login --service-principal \
    --username "$AZURE_CLIENT_ID" \
    --password "$AZURE_CLIENT_SECRET" \
    --tenant "$AZURE_TENANT_ID" >/dev/null

ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query "username" -o tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv)

if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then
    echo "Failed to retrieve Azure Container Registry credentials" >&2
    exit 1
fi

cat <<EOF > /shared/azure-service-principal.env
AZURE_CLIENT_ID=$AZURE_CLIENT_ID
AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET
AZURE_TENANT_ID=$AZURE_TENANT_ID
ACR_NAME=$ACR_NAME
ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER
AZURE_STORAGE_CONNECTION_STRING=$AZURE_STORAGE_CONNECTION_STRING
EOF

echo "$ACR_USERNAME" > /shared/acr-username.txt
echo "$ACR_PASSWORD" > /shared/acr-password.txt

touch /shared/done


