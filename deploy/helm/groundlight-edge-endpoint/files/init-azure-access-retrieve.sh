#!/bin/bash

# Part one of getting Azure credentials set up.
# This script runs in an az-cli container and retrieves the credentials from the IntelliOptics cloud service.
# Then it writes the Azure Storage connection info and the Azure Container Registry credentials
# to a shared volume for the second stage to apply inside the cluster.

set -euo pipefail

if [ "${1:-}" == "validate" ]; then
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

if [ "${validate:-no}" == "yes" ]; then
  echo "API token validation successful. Exiting."
  exit 0
fi

STORAGE_CONNECTION_STRING=$(jq -r '.storage_connection_string' /tmp/credentials.json)
STORAGE_CONTAINER=$(jq -r '.storage_container' /tmp/credentials.json)
ACR_LOGIN_SERVER=$(jq -r '.acr_login_server' /tmp/credentials.json)
ACR_USERNAME=$(jq -r '.acr_username' /tmp/credentials.json)
ACR_PASSWORD=$(jq -r '.acr_password' /tmp/credentials.json)

if [ -z "$STORAGE_CONNECTION_STRING" ] || [ -z "$STORAGE_CONTAINER" ]; then
  echo "Storage credentials missing from response" >&2
  exit 1
fi

if [ -z "$ACR_LOGIN_SERVER" ] || [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then
  echo "ACR credentials missing from response" >&2
  exit 1
fi

echo "$STORAGE_CONNECTION_STRING" > /shared/storage_connection_string
printf "%s" "$STORAGE_CONTAINER" > /shared/storage_container
printf "%s" "$ACR_LOGIN_SERVER" > /shared/acr_login_server
printf "%s" "$ACR_USERNAME" > /shared/acr_username
printf "%s" "$ACR_PASSWORD" > /shared/acr_password

cat <<'INNER' > /shared/storage.env
AZURE_STORAGE_CONNECTION_STRING="$STORAGE_CONNECTION_STRING"
AZURE_STORAGE_CONTAINER="$STORAGE_CONTAINER"
INNER

echo "Credentials fetched and written to shared volume"

touch /shared/done

