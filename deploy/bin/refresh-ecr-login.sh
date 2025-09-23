#!/bin/bash

set -euo pipefail

log() {
    echo "$@" >&2
}

fail() {
    echo "Error: $@" >&2
    exit 1
}

K=${KUBECTL_CMD:-"kubectl"}

ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-"acrintellioptics.azurecr.io"}
if [[ -z "$ACR_LOGIN_SERVER" ]]; then
    fail "ACR_LOGIN_SERVER is required"
fi

# Allow the user to explicitly set the ACR name. If it's not set, derive it from the login server.
if [[ -n "${ACR_NAME:-}" ]]; then
    ACR_NAME="$ACR_NAME"
else
    ACR_NAME=${ACR_LOGIN_SERVER%%.*}
    if [[ -z "$ACR_NAME" ]]; then
        fail "Unable to determine ACR_NAME from ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER"
    fi
fi

# Normalize boolean environment variables that toggle managed identity usage.
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

ensure_acr_credentials() {
    if [[ -n "${ACR_PASSWORD:-}" ]]; then
        if [[ -z "${ACR_USERNAME:-}" ]]; then
            ACR_USERNAME="00000000-0000-0000-0000-000000000000"
        fi
        return 0
    fi

    if [[ -n "${ACR_USERNAME:-}" && -n "${ACR_PASSWORD_FILE:-}" && -f "$ACR_PASSWORD_FILE" ]]; then
        ACR_PASSWORD=$(<"$ACR_PASSWORD_FILE")
        return 0
    fi

    if [[ -n "${ACR_USERNAME:-}" && -n "${ACR_PASSWORD:-}" ]]; then
        return 0
    fi

    if ! command -v az >/dev/null 2>&1; then
        fail "No ACR credentials provided and Azure CLI is not available"
    fi

    if ! az account show >/dev/null 2>&1; then
        ensure_az_login || fail "Azure CLI is not logged in. Provide service principal credentials or enable managed identity."
    fi

    log "Requesting temporary ACR access token for $ACR_NAME"
    local access_token
    access_token=$(az acr login --name "$ACR_NAME" --expose-token --output tsv --query accessToken)
    if [[ -z "$access_token" ]]; then
        fail "Failed to obtain an access token for ACR registry $ACR_NAME"
    fi

    if [[ -z "${ACR_USERNAME:-}" ]]; then
        local username
        username=$(az acr login --name "$ACR_NAME" --expose-token --output tsv --query username 2>/dev/null || true)
        if [[ -z "$username" ]]; then
            username="00000000-0000-0000-0000-000000000000"
        fi
        ACR_USERNAME="$username"
    fi

    ACR_PASSWORD="$access_token"
}

ensure_acr_credentials

log "Using Azure Container Registry $ACR_LOGIN_SERVER (name: $ACR_NAME)"

if command -v docker >/dev/null 2>&1; then
    log "Logging docker into $ACR_LOGIN_SERVER"
    echo "$ACR_PASSWORD" | docker login \
        --username "$ACR_USERNAME" \
        --password-stdin \
        "$ACR_LOGIN_SERVER"
else
    log "Docker is not installed. Skipping local docker login."
fi

log "Refreshing Kubernetes secret registry-credentials"
$K delete --ignore-not-found secret registry-credentials >/dev/null 2>&1 || true
$K create secret docker-registry registry-credentials \
    --docker-server="$ACR_LOGIN_SERVER" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD" \
    --dry-run=client -o yaml | $K apply -f -

log "Stored ACR credentials in secret registry-credentials"
