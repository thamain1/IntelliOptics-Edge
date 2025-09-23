#!/bin/bash

# Part one of getting Azure credentials set up.
# This script runs in an Azure CLI container and retrieves the credentials from the IntelliOptics
# cloud service. The credentials include the Azure service principal, storage account details, and
# container registry metadata required by other jobs.
#
# It saves two files to the shared volume for use by part two:
# 1. /shared/azure.env: A shell-compatible environment file containing Azure credentials.
# 2. /shared/done: A marker file to indicate that the script has completed successfully.

# Note: This script is also used to validate the INTELLIOPTICS_API_TOKEN and INTELLIOPTICS_ENDPOINT
# settings. If you run it with the first argument being "validate", it will only run through the 
# check of the curl results and exit with 0 if they are valid or 1 if they are not. In the latter 
# case, it will also log the results.

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

echo "Fetching temporary Azure credentials from the IntelliOptics cloud service..."
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

extract_credential() {
    local jq_query="$1"
    jq -r "${jq_query} // empty" /tmp/credentials.json
}

AZURE_CLIENT_ID=$(extract_credential '.azure_client_id')
AZURE_CLIENT_SECRET=$(extract_credential '.azure_client_secret')
AZURE_TENANT_ID=$(extract_credential '.azure_tenant_id')
AZURE_SUBSCRIPTION_ID=$(extract_credential '.azure_subscription_id')
AZURE_STORAGE_ACCOUNT=$(extract_credential '.azure_storage_account')
AZURE_STORAGE_KEY=$(extract_credential '.azure_storage_key')
AZURE_STORAGE_CONTAINER=$(extract_credential '.azure_storage_container')
ACR_LOGIN_SERVER=$(extract_credential '.acr_login_server')
ACR_NAME=$(extract_credential '.acr_name')

if [ -z "$ACR_LOGIN_SERVER" ]; then
    ACR_LOGIN_SERVER="{{ .Values.acrLoginServer }}"
fi

if [ -z "$ACR_NAME" ] && [ -n "$ACR_LOGIN_SERVER" ]; then
    ACR_NAME=${ACR_LOGIN_SERVER%%.azurecr.io}
fi

for required in \
    AZURE_CLIENT_ID \
    AZURE_CLIENT_SECRET \
    AZURE_TENANT_ID \
    AZURE_STORAGE_ACCOUNT \
    AZURE_STORAGE_KEY \
    AZURE_STORAGE_CONTAINER \
    ACR_LOGIN_SERVER \
    ACR_NAME; do
    if [ -z "${!required}" ]; then
        echo "Required credential $required missing from response" >&2
        exit 1
    fi
done

cat <<EOF > /shared/azure.env
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT}
AZURE_STORAGE_KEY=${AZURE_STORAGE_KEY}
AZURE_STORAGE_CONTAINER=${AZURE_STORAGE_CONTAINER}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER}
ACR_NAME=${ACR_NAME}
EOF

echo "Credentials fetched and saved to /shared/azure.env"

touch /shared/done


