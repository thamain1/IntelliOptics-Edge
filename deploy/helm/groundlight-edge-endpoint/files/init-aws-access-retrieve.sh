#!/bin/bash

# Part one of getting AWS credentials set up.
# This script runs in a aws-cli container and retrieves the credentials from Janzu.
# Then it uses the credentials to get a login token for ECR.
#
# It saves three files to the shared volume for use by part two:
# 1. /shared/credentials: The AWS credentials file that can be mounted into pods at ~/.aws/credentials
# 2. /shared/token.txt: The ECR login token that can be used to pull images from ECR. This will
#    be used to create a registry secret in k8s.
# 3. /shared/done: A marker file to indicate that the script has completed successfully.

# Note: This script is also used to validate the INTELLIOPTICS_API_TOKEN and INTELLIOPTICS_ENDPOINT
# settings. If you run it with the first argument being "validate", it will only run through the
# check of the curl results and exit with 0 if they are valid or 1 if they are not. In the latter
# case, it will also log the results.

# Registry configuration values are passed in via the Helm chart.
REGISTRY_PROVIDER=$(echo "${REGISTRY_PROVIDER:-aws}" | tr '[:upper:]' '[:lower:]')
REGISTRY_SERVER="${REGISTRY_SERVER:-}"
AZURE_REGISTRY_NAME="${AZURE_REGISTRY_NAME:-}"

derive_azure_login_server() {
  if ! command -v az >/dev/null 2>&1; then
    echo "Azure CLI (az) is required to derive the Azure registry login server." >&2
    return 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to parse the Azure login server response." >&2
    return 1
  fi

  local login_output
  if ! login_output=$(az acr login --name "$AZURE_REGISTRY_NAME" --expose-token --output json); then
    echo "Failed to fetch Azure Container Registry login details for '$AZURE_REGISTRY_NAME'." >&2
    return 1
  fi

  local derived_server
  if ! derived_server=$(printf '%s' "$login_output" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("loginServer", ""))'); then
    echo "Failed to parse Azure Container Registry login server." >&2
    return 1
  fi

  if [[ -z "$derived_server" || "$derived_server" == "None" || "$derived_server" == "null" ]]; then
    echo "Azure login response did not include a loginServer." >&2
    return 1
  fi

  REGISTRY_SERVER="$derived_server"
  export REGISTRY_SERVER
  echo "Using Azure Container Registry server: $REGISTRY_SERVER"
}

if [[ "$REGISTRY_PROVIDER" == "azure" ]]; then
  if [[ -z "$AZURE_REGISTRY_NAME" ]]; then
    echo "AZURE_REGISTRY_NAME must be provided when REGISTRY_PROVIDER is 'azure'." >&2
    exit 1
  fi

  if [[ -z "$REGISTRY_SERVER" || ! "$REGISTRY_SERVER" =~ \.azurecr\.io$ ]]; then
    if ! derive_azure_login_server; then
      echo "Failed to determine Azure Container Registry login server." >&2
      exit 1
    fi
  fi
fi

if [[ -n "$REGISTRY_SERVER" ]]; then
  echo "$REGISTRY_SERVER" > /shared/registry-server
fi

if [ "$1" == "validate" ]; then
  echo "Validating INTELLIOPTICS_API_TOKEN and INTELLIOPTICS_ENDPOINT..."
  if [ -z "$INTELLIOPTICS_API_TOKEN" ]; then
    echo "INTELLIOPTICS_API_TOKEN is not set. Exiting."
    exit 1
  fi

  if [ -z "$INTELLIOPTICS_ENDPOINT" ]; then
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

sanitized_url=$(sanitize_endpoint_url "${INTELLIOPTICS_ENDPOINT}")
echo "Sanitized URL: $sanitized_url"

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

if [ "$validate" == "yes" ]; then

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

echo "Fetching AWS ECR login token..."
TOKEN=$(aws ecr get-login-password --region {{ .Values.awsRegion }})
echo $TOKEN > /shared/token.txt

echo "Token fetched and saved to /shared/token.txt"

touch /shared/done


