#!/bin/bash

# Part one of setting up container registry access for the edge endpoint.
# This script runs in an Azure CLI container and retrieves credentials from
# one of three possible sources:
#   1. Pre-provided ACR credentials (ACR_USERNAME/ACR_PASSWORD)
#   2. Service principal credentials (AZURE_CLIENT_ID/AZURE_CLIENT_SECRET/AZURE_TENANT_ID)
#   3. Managed identity credentials (AZURE_USE_MANAGED_IDENTITY=true, optional IDENTITY_CLIENT_ID)
#
# It stores the resolved registry credentials on the shared volume for
# init-aws-access-apply.sh (part two) to consume.
#
# The script also supports a "validate" mode used by the Helm pre-install
# hooks to verify the IntelliOptics API token.

set -euo pipefail

validate="no"
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

log() {
    echo "$@" >&2
}

should_use_managed_identity() {
    case "${AZURE_USE_MANAGED_IDENTITY:-false}" in
        1|true|TRUE|True|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_az_login() {
    if ! command -v az >/dev/null 2>&1; then
        return 1
    fi

    if az account show >/dev/null 2>&1; then
        return 0
    fi

    if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" && -n "${AZURE_TENANT_ID:-}" ]]; then
        log "Logging into Azure with provided service principal credentials"
        az login --service-principal \
            --username "$AZURE_CLIENT_ID" \
            --password "$AZURE_CLIENT_SECRET" \
            --tenant "$AZURE_TENANT_ID" \
            >/dev/null
        return 0
    fi

    if should_use_managed_identity; then
        log "Logging into Azure using managed identity"
        if [[ -n "${IDENTITY_CLIENT_ID:-}" ]]; then
            az login --identity --username "$IDENTITY_CLIENT_ID" >/dev/null
        else
            az login --identity >/dev/null
        fi
        return 0
    fi

    return 1
}

resolve_acr_settings() {
    if [[ -z "${ACR_LOGIN_SERVER:-}" ]]; then
        ACR_LOGIN_SERVER="acrintellioptics.azurecr.io"
    fi

    if [[ -z "${ACR_NAME:-}" ]]; then
        ACR_NAME=${ACR_LOGIN_SERVER%%.*}
    fi

    if [[ -z "$ACR_NAME" ]]; then
        echo "Unable to determine ACR_NAME" >&2
        exit 1
    fi

    if [[ -n "${ACR_PASSWORD:-}" && -z "${ACR_USERNAME:-}" ]]; then
        ACR_USERNAME="00000000-0000-0000-0000-000000000000"
    fi

    if [[ -z "${ACR_USERNAME:-}" || -z "${ACR_PASSWORD:-}" ]]; then
        if command -v az >/dev/null 2>&1; then
            if ! az account show >/dev/null 2>&1; then
                ensure_az_login || {
                    echo "Azure CLI is not logged in. Provide service principal credentials or enable managed identity." >&2
                    exit 1
                }
            fi

            log "Requesting temporary ACR access token for $ACR_NAME"
            ACR_PASSWORD=$(az acr login --name "$ACR_NAME" --expose-token --output tsv --query accessToken)
            if [[ -z "$ACR_PASSWORD" ]]; then
                echo "Failed to obtain access token for $ACR_NAME" >&2
                exit 1
            fi

            if [[ -z "${ACR_USERNAME:-}" ]]; then
                ACR_USERNAME=$(az acr login --name "$ACR_NAME" --expose-token --output tsv --query username 2>/dev/null || true)
                if [[ -z "$ACR_USERNAME" ]]; then
                    ACR_USERNAME="00000000-0000-0000-0000-000000000000"
                fi
            fi
        else
            echo "Azure CLI is not available and static ACR credentials were not provided" >&2
            exit 1
        fi
    fi
}

sanitized_url=$(sanitize_endpoint_url "${INTELLIOPTICS_ENDPOINT:-}")
log "Sanitized URL: $sanitized_url"

if [ "$validate" == "yes" ]; then
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

  echo "API token validation successful. Exiting."
  exit 0
fi

resolve_acr_settings

log "Writing registry credentials to shared volume"
cat <<EOF_SHARED > /shared/registry.env
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER}
ACR_NAME=${ACR_NAME}
ACR_USERNAME=${ACR_USERNAME}
ACR_PASSWORD=${ACR_PASSWORD}
EOF_SHARED

if command -v docker >/dev/null 2>&1; then
    log "Logging docker into ${ACR_LOGIN_SERVER}"
    echo "${ACR_PASSWORD}" | docker login \
        --username "${ACR_USERNAME}" \
        --password-stdin \
        "${ACR_LOGIN_SERVER}"
else
    log "Docker is not installed. Skipping local docker login."
fi

touch /shared/done
