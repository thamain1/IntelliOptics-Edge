#!/bin/bash
set -euo pipefail

# Part one of getting registry credentials set up.
# This script runs in a utility container and retrieves the credentials from Janzu.
# Then it uses the configured cloud provider tooling to get a login token for the
# container registry and emits a Docker config.json that can be stored as a pull
# secret.
#
# It saves three files to the shared volume for use by part two:
# 1. /shared/credentials: The AWS credentials file that can be mounted into pods at ~/.aws/credentials
# 2. /shared/token.txt: The short-lived registry token/password used to create the docker config.
# 3. /shared/config.json: Docker configuration JSON that can be stored as a kubernetes.io/dockerconfigjson secret.
# 4. /shared/done: A marker file to indicate that the script has completed successfully.
#
# Note: This script is also used to validate the INTELLIOPTICS_API_TOKEN and INTELLIOPTICS_ENDPOINT
# settings. If you run it with the first argument being "validate", it will only run through the
# check of the curl results and exit with 0 if they are valid or 1 if they are not. In the latter
# case, it will also log the results.

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

REGISTRY_PROVIDER=${REGISTRY_PROVIDER:-aws}
REGISTRY_SERVER=${REGISTRY_SERVER:-${ECR_REGISTRY:-}}
REGISTRY_SECRET_NAME=${REGISTRY_SECRET_NAME:-registry-credentials}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-}
REGISTRY_PASSWORD_CMD=${REGISTRY_PASSWORD_CMD:-}
AWS_REGION=${AWS_REGION:-us-west-2}
AZURE_REGISTRY_NAME=${AZURE_REGISTRY_NAME:-}
AZURE_LOGIN_MODE=${AZURE_LOGIN_MODE:-servicePrincipal}

CONFIG_JSON_PATH=/shared/config.json
TOKEN_PATH=/shared/token.txt

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_binary() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Required binary '$1' is not installed"
  fi
}

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

derive_azure_registry_name() {
  if [ -n "$AZURE_REGISTRY_NAME" ]; then
    echo "$AZURE_REGISTRY_NAME"
    return 0
  fi
  if [[ -z "$REGISTRY_SERVER" ]]; then
    return 1
  fi
  local domain="$REGISTRY_SERVER"
  domain="${domain%%:*}"
  if [[ "$domain" =~ ^([^.]+)\.azurecr\.io$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

azure_login() {
  require_binary az
  local mode="$AZURE_LOGIN_MODE"
  case "$mode" in
    servicePrincipal)
      if [ -z "${AZURE_CLIENT_ID:-}" ] || [ -z "${AZURE_CLIENT_SECRET:-}" ] || [ -z "${AZURE_TENANT_ID:-}" ]; then
        die "AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, and AZURE_TENANT_ID must be set for service principal login"
      fi
      log "Logging in to Azure using service principal"
      az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" >/tmp/az-login.log 2>&1 || {
        cat /tmp/az-login.log >&2
        die "az login failed"
      }
      ;;
    workloadIdentity)
      log "Logging in to Azure using workload identity"
      az login --identity >/tmp/az-login.log 2>&1 || {
        cat /tmp/az-login.log >&2
        die "az login (workload identity) failed"
      }
      ;;
    none)
      log "Skipping Azure login as requested"
      ;;
    *)
      log "Logging in to Azure using custom mode '$mode'"
      az login $mode >/tmp/az-login.log 2>&1 || {
        cat /tmp/az-login.log >&2
        die "az login failed"
      }
      ;;
  esac
}

write_docker_config() {
  local username="$1"
  local password="$2"
  local server="$3"

  if [ -z "$server" ]; then
    die "REGISTRY_SERVER is not set"
  fi

  local auth
  auth=$(printf '%s' "$username:$password" | base64 | tr -d '\n')
  cat <<EOF > "$CONFIG_JSON_PATH"
{
  "auths": {
    "$server": {
      "username": "$username",
      "password": "$password",
      "auth": "$auth"
    }
  }
}
EOF
}

sanitized_url=$(sanitize_endpoint_url "${INTELLIOPTICS_ENDPOINT:-}")
log "Sanitized URL: $sanitized_url"

log "Fetching temporary AWS credentials from the IntelliOptics cloud service..."
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
  log "API token validation successful. Exiting."
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

log "Credentials fetched and saved to /shared/credentials"
cat /shared/credentials; echo

log "Generating registry credentials for provider '$REGISTRY_PROVIDER'"
case "$REGISTRY_PROVIDER" in
  aws)
    require_binary aws
    if [ -z "$REGISTRY_PASSWORD_CMD" ]; then
      REGISTRY_PASSWORD_CMD="aws ecr get-login-password --region ${AWS_REGION}"
    fi
    if [ -z "$REGISTRY_USERNAME" ]; then
      REGISTRY_USERNAME="AWS"
    fi
    ;;
  azure)
    azure_login
    if [ -z "$REGISTRY_USERNAME" ]; then
      REGISTRY_USERNAME="00000000-0000-0000-0000-000000000000"
    fi
    if [ -z "$REGISTRY_PASSWORD_CMD" ]; then
      local registry_name
      registry_name=$(derive_azure_registry_name)
      if [ -z "$registry_name" ]; then
        die "Unable to determine Azure registry name. Set AZURE_REGISTRY_NAME or REGISTRY_PASSWORD_CMD."
      fi
      REGISTRY_PASSWORD_CMD="az acr login --name ${registry_name} --expose-token --output tsv --query accessToken"
    fi
    ;;
  generic)
    if [ -z "$REGISTRY_USERNAME" ]; then
      die "REGISTRY_USERNAME must be set when using generic provider"
    fi
    if [ -z "$REGISTRY_PASSWORD_CMD" ]; then
      die "REGISTRY_PASSWORD_CMD must be set when using generic provider"
    fi
    ;;
  *)
    die "Unknown REGISTRY_PROVIDER '$REGISTRY_PROVIDER'"
    ;;
 esac

if [ -z "$REGISTRY_PASSWORD_CMD" ]; then
  die "REGISTRY_PASSWORD_CMD is empty"
fi

log "Running password command for registry"
set +o pipefail
REGISTRY_PASSWORD=$(eval "$REGISTRY_PASSWORD_CMD")
STATUS=$?
set -o pipefail
if [ $STATUS -ne 0 ]; then
  die "Failed to fetch registry password using command: $REGISTRY_PASSWORD_CMD"
fi

echo -n "$REGISTRY_PASSWORD" > "$TOKEN_PATH"

write_docker_config "$REGISTRY_USERNAME" "$REGISTRY_PASSWORD" "$REGISTRY_SERVER"

log "Token fetched and saved to $TOKEN_PATH"
log "Docker config written to $CONFIG_JSON_PATH"

touch /shared/done
