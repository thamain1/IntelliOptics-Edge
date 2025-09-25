#!/bin/bash

set -euo pipefail

# Part one of getting Azure Container Registry credentials set up.
# This script runs in a CLI container and retrieves the credentials from the
# IntelliOptics cloud service.
#
# It saves two files to the shared volume for use by part two:
# 1. /shared/registry.env: environment variables with the registry server,
#    username, and password.
# 2. /shared/done: A marker file to indicate that the script has completed
#    successfully.
#
# Note: This script is also used to validate the INTELLIOPTICS_API_TOKEN and
# INTELLIOPTICS_ENDPOINT settings. If you run it with the first argument being
# "validate", it will only run through the check of the curl results and exit
# with 0 if they are valid or 1 if they are not. In the latter case, it will
# also log the results.

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

sanitized_url=$(sanitize_endpoint_url "${INTELLIOPTICS_ENDPOINT:-}")
echo "Sanitized URL: $sanitized_url"

echo "Fetching registry credentials from the IntelliOptics cloud service..."
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

if [ "${validate:-}" == "yes" ]; then
  echo "API token validation successful. Exiting."
  exit 0
fi

readarray -t REGISTRY_DATA < <(python3 - <<'PY'
import json
from pathlib import Path

def first(data, *keys):
    for key in keys:
        cur = data
        found = True
        for part in key.split('.'):
            if isinstance(cur, dict) and part in cur:
                cur = cur[part]
            else:
                found = False
                break
        if found and cur:
            return cur
    return ""

with Path("/tmp/credentials.json").open() as fh:
    payload = json.load(fh)

server = first(payload, "registry", "registry_url", "registry.server", "registryServer")
username = first(payload, "registry_username", "username", "registry.username", "acr_username")
password = first(payload, "registry_password", "password", "registry.password", "acr_password")
print(server)
print(username)
print(password)
PY
)

AZURE_REGISTRY=${REGISTRY_DATA[0]}
AZURE_REGISTRY_USERNAME=${REGISTRY_DATA[1]}
AZURE_REGISTRY_PASSWORD=${REGISTRY_DATA[2]}

if [ -z "$AZURE_REGISTRY" ]; then
  AZURE_REGISTRY="{{ .Values.azureRegistry }}"
fi

if [ -z "$AZURE_REGISTRY" ] || [ -z "$AZURE_REGISTRY_USERNAME" ] || [ -z "$AZURE_REGISTRY_PASSWORD" ]; then
  echo "Failed to parse registry credentials from payload" >&2
  cat /tmp/credentials.json >&2
  exit 1
fi

cat <<ENV > /shared/registry.env
AZURE_REGISTRY="$AZURE_REGISTRY"
AZURE_REGISTRY_USERNAME="$AZURE_REGISTRY_USERNAME"
AZURE_REGISTRY_PASSWORD="$AZURE_REGISTRY_PASSWORD"
ENV

echo "Credentials fetched and saved to /shared/registry.env"

touch /shared/done

