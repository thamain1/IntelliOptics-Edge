#!/bin/bash

# Shared helpers for authenticating with Azure Container Registry. Scripts sourcing
# this file should run `azure_acr_login` before attempting to push/pull images.

ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-${ACR_NAME:-acrintellioptics.azurecr.io}}
# If the login server uses the standard Azure format (<name>.azurecr.io), derive the
# registry name automatically. Otherwise allow callers to provide ACR_REGISTRY_NAME.
if [[ -z "${ACR_REGISTRY_NAME:-}" ]]; then
  if [[ "$ACR_LOGIN_SERVER" == *.azurecr.io ]]; then
    ACR_REGISTRY_NAME=${ACR_LOGIN_SERVER%%.azurecr.io}
  else
    ACR_REGISTRY_NAME=$ACR_LOGIN_SERVER
  fi
fi

azure_acr_login() {
  local login_server="${1:-$ACR_LOGIN_SERVER}"
  local registry_name="${2:-$ACR_REGISTRY_NAME}"

  if command -v az >/dev/null 2>&1; then
    if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_TENANT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" ]]; then
      az login --service-principal \
        --username "$AZURE_CLIENT_ID" \
        --password "$AZURE_CLIENT_SECRET" \
        --tenant "$AZURE_TENANT_ID" >/dev/null 2>&1 || true
    fi

    if az acr login --name "$registry_name" >/dev/null 2>&1; then
      return 0
    fi

    if [[ "$registry_name" != "$login_server" ]]; then
      if az acr login --name "$login_server" >/dev/null 2>&1; then
        return 0
      fi
    fi
  fi

  if [[ -n "${ACR_USERNAME:-}" && -n "${ACR_PASSWORD:-}" ]]; then
    echo "$ACR_PASSWORD" | docker login "$login_server" --username "$ACR_USERNAME" --password-stdin
    return 0
  fi

  echo "Error: Unable to authenticate with Azure Container Registry. Provide Azure CLI access or ACR_USERNAME/ACR_PASSWORD." >&2
  return 1
}
