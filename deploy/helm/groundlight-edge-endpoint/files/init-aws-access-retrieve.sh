#!/bin/bash

set -euo pipefail

REGISTRY_PROVIDER=$(echo "${REGISTRY_PROVIDER:-azure}" | tr '[:upper:]' '[:lower:]')

if [[ "$REGISTRY_PROVIDER" != "azure" ]]; then
  echo "Unsupported REGISTRY_PROVIDER '$REGISTRY_PROVIDER'. Supported providers: azure" >&2
  exit 1
fi

exec /bin/bash /app/init-azure-access-retrieve.sh "$@"
SHARED_DIR=${SHARED_DIR:-/shared}
REGISTRY_PROVIDER=${REGISTRY_PROVIDER:-aws}
DONE_FILE="${DONE_FILE:-${SHARED_DIR}/done}"
REGISTRY_SERVER_FILE="${REGISTRY_SERVER_FILE:-${SHARED_DIR}/registry-server}"
REGISTRY_USERNAME_FILE="${REGISTRY_USERNAME_FILE:-${SHARED_DIR}/registry-username}"
REGISTRY_TOKEN_FILE="${REGISTRY_TOKEN_FILE:-${SHARED_DIR}/token.txt}"

mkdir -p "${SHARED_DIR}"

validate_only=""
if [ "${1:-}" = "validate" ]; then
  validate_only="yes"
fi

if [ "${REGISTRY_PROVIDER}" = "azure" ]; then
  if ! command -v az >/dev/null 2>&1; then
    echo "Azure CLI (az) is required to retrieve registry credentials" >&2
    exit 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for parsing credential responses" >&2
    exit 1
  fi

  sanitize_endpoint_url() {
    local endpoint="${1:-$INTELLIOPTICS_ENDPOINT}"

    if [[ -z "$endpoint" ]]; then
      endpoint="https://intellioptics-api-37558.azurewebsites.net/"
    fi

    if [[ "$endpoint" =~ ^(https?)://([^/]+)(/.*)?$ ]]; then
      local scheme="${BASH_REMATCH[1]}"
      local netloc="${BASH_REMATCH[2]}"
      local path="${BASH_REMATCH[3]}"

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
        "/device-api/"|"/v1/"|"/v2/"|"/v3/") ;;
        *)
          echo "Warning: Configured endpoint $endpoint does not look right - path '$path' seems wrong." >&2
          ;;
      esac

      sanitized_endpoint="${scheme}://${netloc}${path%/}"
      echo "$sanitized_endpoint"
    else
      echo "Invalid API endpoint: $endpoint. Must be a valid URL with http or https scheme." >&2
      exit 1
    fi
  }

  sanitized_url=$(sanitize_endpoint_url "${INTELLIOPTICS_ENDPOINT:-}")

  if [ -z "${INTELLIOPTICS_API_TOKEN:-}" ]; then
    echo "INTELLIOPTICS_API_TOKEN is not set. Exiting." >&2
    exit 1
  fi

  echo "Fetching Azure service principal credentials from the IntelliOptics cloud service..."
  HTTP_STATUS=$(curl -s -L -o /tmp/credentials.json -w "%{http_code}" --fail-with-body --header "x-api-token: ${INTELLIOPTICS_API_TOKEN}" "${sanitized_url}/reader-credentials") || {
    echo "Failed to fetch credentials from the IntelliOptics cloud service" >&2
    if [ -n "$HTTP_STATUS" ]; then
      echo "HTTP Status: $HTTP_STATUS" >&2
    fi
    echo -n "Response: " >&2
    cat /tmp/credentials.json >&2
    echo >&2
    exit 1
  }

  if [ "$validate_only" = "yes" ]; then
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
print(get("acr_name", ""))
print(get("acr_login_server", ""))
print(get("azure_storage_connection_string", ""))
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

  if [ -z "$ACR_NAME" ] && [ -n "$ACR_LOGIN_SERVER" ]; then
    ACR_NAME="${ACR_LOGIN_SERVER%%.azurecr.io}"
  fi

  if [ -z "$ACR_NAME" ]; then
    echo "ACR_NAME was not provided in the credential response" >&2
    exit 1
  fi

  if [ -z "$ACR_LOGIN_SERVER" ]; then
    ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
  fi

  echo "Logging into Azure Container Registry '$ACR_NAME' to obtain an access token..."
  az login --service-principal \
    --username "$AZURE_CLIENT_ID" \
    --password "$AZURE_CLIENT_SECRET" \
    --tenant "$AZURE_TENANT_ID" >/dev/null

  login_json=$(az acr login --name "$ACR_NAME" --expose-token --output json)

  mapfile -t login_fields < <(python3 <<'PY'
import json
import sys

data = json.loads(sys.stdin.read())

server = data.get("loginServer") or data.get("registry") or data.get("acrLoginServer") or ""
username = data.get("username") or data.get("userName") or data.get("name") or ""
password = data.get("accessToken") or data.get("password") or data.get("token") or ""

passwords = data.get("passwords")
if (not password) and isinstance(passwords, list) and passwords:
    password = passwords[0].get("value") or passwords[0].get("password") or ""

print(server)
print(username)
print(password)
PY
  <<<"$login_json")

  LOGIN_SERVER="${login_fields[0]}"
  LOGIN_USERNAME="${login_fields[1]}"
  LOGIN_PASSWORD="${login_fields[2]}"

  if [ -z "$LOGIN_SERVER" ]; then
    LOGIN_SERVER="$ACR_LOGIN_SERVER"
  fi

  if [ -z "$LOGIN_USERNAME" ] || [ -z "$LOGIN_PASSWORD" ]; then
    echo "Failed to retrieve Azure Container Registry credentials" >&2
    exit 1
  fi

  cat <<ENV > "${SHARED_DIR}/azure-service-principal.env"
AZURE_CLIENT_ID=$AZURE_CLIENT_ID
AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET
AZURE_TENANT_ID=$AZURE_TENANT_ID
ACR_NAME=$ACR_NAME
ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER
AZURE_STORAGE_CONNECTION_STRING=$AZURE_STORAGE_CONNECTION_STRING
ENV

  printf '%s' "$LOGIN_SERVER" > "$REGISTRY_SERVER_FILE"
  printf '%s' "$LOGIN_USERNAME" > "$REGISTRY_USERNAME_FILE"
  printf '%s' "$LOGIN_PASSWORD" > "$REGISTRY_TOKEN_FILE"
  printf '%s' "$LOGIN_USERNAME" > "${SHARED_DIR}/acr-username.txt"
  printf '%s' "$LOGIN_PASSWORD" > "${SHARED_DIR}/acr-password.txt"

  touch "$DONE_FILE"
  exit 0
fi

if [ "$validate_only" = "yes" ]; then
  echo "Validation for AWS path is not implemented separately. Assuming credentials are managed externally."
  exit 0
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required to retrieve ECR credentials" >&2
  exit 1
fi

REGION="${ECR_REGION:-${AWS_REGION:-}}"
if [ -z "$REGION" ]; then
  echo "ECR region is not set. Provide ECR_REGION or AWS_REGION." >&2
  exit 1
fi

ECR_REGISTRY_URL="${ECR_REGISTRY:-}"
if [ -z "$ECR_REGISTRY_URL" ]; then
  if [ -n "${AWS_ACCOUNT_ID:-}" ]; then
    ECR_REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
  else
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
      echo "Unable to determine AWS account ID for ECR registry" >&2
      exit 1
    fi
    ECR_REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
  fi
fi

PASSWORD=$(aws ecr get-login-password --region "$REGION")
if [ -z "$PASSWORD" ]; then
  echo "Failed to retrieve AWS ECR password" >&2
  exit 1
fi

printf '%s' "$ECR_REGISTRY_URL" > "$REGISTRY_SERVER_FILE"
printf '%s' "AWS" > "$REGISTRY_USERNAME_FILE"
printf '%s' "$PASSWORD" > "$REGISTRY_TOKEN_FILE"

touch "$DONE_FILE"
