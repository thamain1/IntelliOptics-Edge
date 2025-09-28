#!/bin/bash

set -euo pipefail

DEFAULT_PROVIDER="azure"

REGISTRY_PROVIDER="${REGISTRY_PROVIDER:-}"
if [[ -z "$REGISTRY_PROVIDER" ]]; then
  if [[ -n "${AZURE_CLIENT_ID:-}" || -n "${AZURE_TENANT_ID:-}" || -n "${AZURE_CLIENT_SECRET:-}" || -n "${ACR_LOGIN_SERVER:-}" || -n "${ACR_NAME:-}" ]]; then
    REGISTRY_PROVIDER="azure"
  elif [[ -n "${AWS_ACCESS_KEY_ID:-}" || -n "${AWS_SECRET_ACCESS_KEY:-}" || -n "${AWS_SESSION_TOKEN:-}" || -n "${AWS_REGION:-}" ]]; then
    REGISTRY_PROVIDER="aws"
  else
    REGISTRY_PROVIDER="$DEFAULT_PROVIDER"
  fi
fi

REGISTRY_PROVIDER=$(echo "$REGISTRY_PROVIDER" | tr '[:upper:]' '[:lower:]')

if [[ "$REGISTRY_PROVIDER" == "azure" ]]; then
  exec /bin/bash /app/init-azure-access-retrieve.sh "$@"
fi

if [[ "$REGISTRY_PROVIDER" != "aws" ]]; then
  echo "Unsupported REGISTRY_PROVIDER '$REGISTRY_PROVIDER'. Supported providers: aws, azure" >&2
  exit 1
fi

validate="no"
if [[ "${1:-}" == "validate" ]]; then
  echo "Validating INTELLIOPTICS_API_TOKEN and INTELLIOPTICS_ENDPOINT..."
  if [[ -z "${INTELLIOPTICS_API_TOKEN:-}" ]]; then
    echo "INTELLIOPTICS_API_TOKEN is not set. Exiting."
    exit 1
  fi

  if [[ -z "${INTELLIOPTICS_ENDPOINT:-}" ]]; then
    echo "INTELLIOPTICS_ENDPOINT is not set. Exiting."
    exit 1
  fi
  validate="yes"
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "The aws CLI is required when REGISTRY_PROVIDER=aws" >&2
  exit 1
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

sanitized_url=$(sanitize_endpoint_url "${INTELLIOPTICS_ENDPOINT:-}")
echo "Sanitized URL: $sanitized_url"

echo "Fetching temporary AWS credentials from the IntelliOptics cloud service..."
HTTP_STATUS=$(curl -s -L -o /tmp/credentials.json -w "%{http_code}" --fail-with-body --header "x-api-token: ${INTELLIOPTICS_API_TOKEN}" ${sanitized_url}/reader-credentials)

if [[ $? -ne 0 ]]; then
  echo "Failed to fetch credentials from the IntelliOptics cloud service"
  if [[ -n "$HTTP_STATUS" ]]; then
    echo "HTTP Status: $HTTP_STATUS"
  fi
  echo -n "Response: "
  cat /tmp/credentials.json; echo
  exit 1
fi

if [[ "$validate" == "yes" ]]; then
  echo "API token validation successful. Exiting."
  exit 0
fi

AWS_ACCESS_KEY_ID=$(sed 's/^.*"access_key_id":"\([^"]*\)".*$/\1/' /tmp/credentials.json)
AWS_SECRET_ACCESS_KEY=$(sed 's/^.*"secret_access_key":"\([^"]*\)".*$/\1/' /tmp/credentials.json)
AWS_SESSION_TOKEN=$(sed 's/^.*"session_token":"\([^"]*\)".*$/\1/' /tmp/credentials.json)
AWS_REGION_VALUE="${AWS_REGION:-{{ .Values.awsRegion }}}"

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION="$AWS_REGION_VALUE"

cat <<'AWS_CREDS' > /shared/credentials
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
aws_session_token = ${AWS_SESSION_TOKEN}
AWS_CREDS

echo "Credentials fetched and saved to /shared/credentials"
cat /shared/credentials; echo

echo "Fetching AWS ECR login token..."
TOKEN=$(aws ecr get-login-password --region "$AWS_REGION_VALUE")
echo "$TOKEN" > /shared/token.txt

echo "Token fetched and saved to /shared/token.txt"

touch /shared/done
