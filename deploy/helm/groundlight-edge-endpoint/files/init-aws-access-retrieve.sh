#!/bin/bash

set -euo pipefail

# Part one of getting cloud credentials set up.
# This script runs in a utility container and retrieves the credentials from the
# IntelliOptics cloud control plane. It also prepares the Docker registry
# authentication material that will be applied to the cluster by
# init-aws-access-apply.sh (part two).
#
# It saves the following files to the shared volume for use by part two:
# 1. /shared/credentials: The AWS credentials file that can be mounted into pods
#    at ~/.aws/credentials. These credentials are required by several workloads
#    regardless of the container registry provider.
# 2. /shared/dockerconfigjson: A docker config JSON file containing pull secret
#    information for the configured registry provider.
# 3. /shared/done: A marker file to indicate that the script has completed
#    successfully.

if [ "${1:-}" == "validate" ]; then
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

# This function replicates the IntelliOptics SDK's logic to clean up user-supplied endpoint URLs
sanitize_endpoint_url() {
    local endpoint="${1:-$INTELLIOPTICS_ENDPOINT}"

    # If empty, set default
    if [[ -z "$endpoint" ]]; then
        endpoint="https://intellioptics-api-37558.azurewebsites.net/"
    fi

    # Parse URL scheme and the rest
    if [[ "$endpoint" =~ ^(https?)://([^/]+)(/.*)?$ ]]; then
        scheme="${BASH_REMATCH[1]}"
        netloc="${BASH_REMATCH[2]}"
        path="${BASH_REMATCH[3]}"
    else
        echo "Invalid API endpoint: $endpoint. Must be a valid URL with http or https scheme." >&2
        exit 1
    fi

    # Ensure path is properly initialized
    if [[ -z "$path" ]]; then
        path="/"
    fi

    # Ensure path ends with "/"
    if [[ "${path: -1}" != "/" ]]; then
        path="$path/"
    fi

    # Set default path if just "/"
    if [[ "$path" == "/" ]]; then
        path="/device-api/"
    fi

    # Allow only specific paths
    case "$path" in
        "/device-api/"|"/v1/"|"/v2/"|"/v3/")
            ;;
        *)
            echo "Warning: Configured endpoint $endpoint does not look right - path '$path' seems wrong." >&2
            ;;
    esac

    # Remove trailing slash for output
    sanitized_endpoint="${scheme}://${netloc}${path%/}"
    echo "$sanitized_endpoint"
}

REGISTRY_PROVIDER=${REGISTRY_PROVIDER:-aws}
REGISTRY_SERVER=${REGISTRY_SERVER:-}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-}
REGISTRY_PASSWORD_COMMAND=${REGISTRY_PASSWORD_COMMAND:-}
REGISTRY_SECRET_NAME=${REGISTRY_SECRET_NAME:-registry-credentials}
REGISTRY_SECRET_TYPE=${REGISTRY_SECRET_TYPE:-kubernetes.io/dockerconfigjson}
AWS_REGION=${AWS_REGION:-{{ .Values.awsRegion }}}
REGISTRY_AWS_REGION=${REGISTRY_AWS_REGION:-$AWS_REGION}
AZURE_LOGIN_MODE=${AZURE_LOGIN_MODE:-service-principal}
AZURE_ACR_NAME=${AZURE_ACR_NAME:-}
AZURE_MANAGED_IDENTITY_CLIENT_ID=${AZURE_MANAGED_IDENTITY_CLIENT_ID:-}

create_docker_config() {
  local server="$1"
  local username="$2"
  local password="$3"

  if [ -z "$server" ] || [ -z "$username" ] || [ -z "$password" ]; then
    echo "Missing information while generating docker config." >&2
    exit 1
  fi

  local auth
  auth=$(printf '%s:%s' "$username" "$password" | base64 | tr -d '\n')

  cat <<JSON > /shared/dockerconfigjson
{
  "auths": {
    "$server": {
      "username": "$username",
      "password": "$password",
      "auth": "$auth"
    }
  }
}
JSON
}

sanitized_url=$(sanitize_endpoint_url "${INTELLIOPTICS_ENDPOINT}")
if [ -n "$sanitized_url" ]; then
  echo "Sanitized URL: $sanitized_url"
fi

echo "Fetching temporary AWS credentials from the IntelliOptics cloud service..."
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

if [ "${validate:-no}" == "yes" ]; then
  echo "API token validation successful. Exiting."
  exit 0
fi

export AWS_ACCESS_KEY_ID=$(sed 's/^.*"access_key_id":"\([^"]*\)".*$/\1/' /tmp/credentials.json)
export AWS_SECRET_ACCESS_KEY=$(sed 's/^.*"secret_access_key":"\([^"]*\)".*$/\1/' /tmp/credentials.json)
export AWS_SESSION_TOKEN=$(sed 's/^.*"session_token":"\([^"]*\)".*$/\1/' /tmp/credentials.json)

cat <<EOF > /shared/credentials
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
aws_session_token = ${AWS_SESSION_TOKEN}
EOF

echo "Credentials fetched and saved to /shared/credentials"
cat /shared/credentials; echo

generate_registry_credentials() {
  case "$REGISTRY_PROVIDER" in
    aws|AWS)
      if ! command -v aws >/dev/null 2>&1; then
        echo "AWS CLI is required for registry provider '$REGISTRY_PROVIDER' but was not found on PATH." >&2
        exit 1
      fi

      local region="$REGISTRY_AWS_REGION"
      if [ -z "$region" ]; then
        echo "AWS region is not configured." >&2
        exit 1
      fi

      local username
      username=${REGISTRY_USERNAME:-AWS}

      local password="$REGISTRY_PASSWORD"
      if [ -z "$password" ]; then
        if [ -n "$REGISTRY_PASSWORD_COMMAND" ]; then
          # shellcheck disable=SC2086
          password=$(eval $REGISTRY_PASSWORD_COMMAND)
        else
          password=$(aws ecr get-login-password --region "$region")
        fi
      fi

      if [ -z "$REGISTRY_SERVER" ]; then
        echo "AWS ECR registry server is not configured." >&2
        exit 1
      fi

      create_docker_config "$REGISTRY_SERVER" "$username" "$password"
      ;;
    azure|AZURE)
      if [ -n "$REGISTRY_PASSWORD_COMMAND" ]; then
        if [ -z "$REGISTRY_USERNAME" ]; then
          echo "REGISTRY_USERNAME must be set when using REGISTRY_PASSWORD_COMMAND for Azure." >&2
          exit 1
        fi
        # shellcheck disable=SC2086
        local password=$(eval $REGISTRY_PASSWORD_COMMAND)
        create_docker_config "${REGISTRY_SERVER:-${AZURE_ACR_NAME}.azurecr.io}" "$REGISTRY_USERNAME" "$password"
        return
      fi

      if ! command -v az >/dev/null 2>&1; then
        echo "Azure CLI is required for registry provider '$REGISTRY_PROVIDER' but was not found on PATH." >&2
        exit 1
      fi

      if [ "${AZURE_LOGIN_MODE}" = "managed-identity" ]; then
        if [ -n "$AZURE_MANAGED_IDENTITY_CLIENT_ID" ]; then
          az login --identity --username "$AZURE_MANAGED_IDENTITY_CLIENT_ID" >/dev/null
        else
          az login --identity >/dev/null
        fi
      else
        if [ -z "${AZURE_CLIENT_ID:-}" ] || [ -z "${AZURE_CLIENT_SECRET:-}" ] || [ -z "${AZURE_TENANT_ID:-}" ]; then
          echo "Azure service principal credentials are required (AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID)." >&2
          exit 1
        fi
        az login --service-principal --username "$AZURE_CLIENT_ID" --password "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" >/dev/null
      fi

      local acr_name="$AZURE_ACR_NAME"
      if [ -z "$acr_name" ] && [ -n "$REGISTRY_SERVER" ]; then
        if [[ "$REGISTRY_SERVER" =~ ^([^.]+)\.azurecr\.io$ ]]; then
          acr_name="${BASH_REMATCH[1]}"
        fi
      fi

      if [ -z "$acr_name" ]; then
        echo "Azure registry name is not configured (set AZURE_ACR_NAME or provide REGISTRY_SERVER ending in .azurecr.io)." >&2
        exit 1
      fi

      local login_json
      login_json=$(mktemp)
      az acr login --name "$acr_name" --expose-token --output json >"$login_json"

      local login_server username password
      login_server=$(sed -n 's/.*"loginServer"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$login_json" | head -n1)
      username=$(sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$login_json" | head -n1)
      password=$(sed -n 's/.*"accessToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$login_json" | head -n1)
      rm -f "$login_json"

      if [ -z "$REGISTRY_SERVER" ]; then
        REGISTRY_SERVER="$login_server"
      fi

      if [ -z "$REGISTRY_SERVER" ] || [ -z "$password" ]; then
        echo "Failed to obtain Azure container registry credentials." >&2
        exit 1
      fi

      if [ -z "$REGISTRY_USERNAME" ]; then
        REGISTRY_USERNAME="$username"
      fi

      create_docker_config "$REGISTRY_SERVER" "$REGISTRY_USERNAME" "$password"
      ;;
    *)
      if [ -z "$REGISTRY_USERNAME" ] || { [ -z "$REGISTRY_PASSWORD_COMMAND" ] && [ -z "$REGISTRY_PASSWORD" ]; }; then
        echo "Unsupported registry provider '$REGISTRY_PROVIDER' without credentials." >&2
        exit 1
      fi

      local password="$REGISTRY_PASSWORD"
      if [ -z "$password" ]; then
        # shellcheck disable=SC2086
        password=$(eval $REGISTRY_PASSWORD_COMMAND)
      fi

      if [ -z "$REGISTRY_SERVER" ]; then
        echo "Registry server must be specified for provider '$REGISTRY_PROVIDER'." >&2
        exit 1
      fi

      create_docker_config "$REGISTRY_SERVER" "$REGISTRY_USERNAME" "$password"
      ;;
  esac
}

generate_registry_credentials

touch /shared/done
