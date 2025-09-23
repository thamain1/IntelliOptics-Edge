#!/bin/bash

set -euo pipefail

if [ "$1" != "validate" ]; then
  echo "Usage: $0 validate" >&2
  exit 1
fi

if [ -z "${INTELLIOPTICS_API_TOKEN:-}" ]; then
  echo "INTELLIOPTICS_API_TOKEN is not set. Exiting." >&2
  exit 1
fi

if [ -z "${INTELLIOPTICS_ENDPOINT:-}" ]; then
  echo "INTELLIOPTICS_ENDPOINT is not set. Exiting." >&2
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
        "/device-api/"|"/v1/"|"/v2/"|"/v3/") ;;
        *)
            echo "Warning: Configured endpoint $endpoint does not look right - path '$path' seems wrong." >&2
            ;;
    esac

    sanitized_endpoint="${scheme}://${netloc}${path%/}"
    echo "$sanitized_endpoint"
}

sanitized_url=$(sanitize_endpoint_url "${INTELLIOPTICS_ENDPOINT}")

echo "Validating INTELLIOPTICS_API_TOKEN against ${sanitized_url}/reader-credentials"

HTTP_STATUS=$(curl -s -L -o /tmp/credentials.json -w "%{http_code}" --fail-with-body --header "x-api-token: ${INTELLIOPTICS_API_TOKEN}" ${sanitized_url}/reader-credentials) || true

if [ "$HTTP_STATUS" != "200" ]; then
  echo "Failed to validate credentials; HTTP status ${HTTP_STATUS}" >&2
  echo -n "Response: " >&2
  cat /tmp/credentials.json >&2
  exit 1
fi

echo "API token validation successful."
