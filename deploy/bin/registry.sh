#!/bin/bash

set -euo pipefail

# Shared registry helper functions for edge endpoint build and tag scripts.
# The deployment pipeline now targets Azure Container Registry exclusively.

registry_require_command() {
  local cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found" >&2
    exit 1
  fi
}

registry__initialize() {
  if [[ -n "${_REGISTRY_INITIALIZED:-}" ]]; then
    return
  fi

  local login_server="${ACR_LOGIN_SERVER:-}"
  local name="${ACR_NAME:-}"

  if [[ -z "$login_server" && -n "$name" ]]; then
    login_server="${name}.azurecr.io"
  fi

  if [[ -z "$name" && -n "$login_server" ]]; then
    name="${login_server%%.*}"
  fi

  if [[ -z "$login_server" ]]; then
    echo "Error: ACR_LOGIN_SERVER or ACR_NAME must be set for Azure registry usage" >&2
    exit 1
  fi

  ACR_NAME="$name"
  ACR_LOGIN_SERVER="$login_server"

  if [[ -n "${ACR_RESOURCE_GROUP:-}" ]]; then
    AZ_ACR_RESOURCE_ARGS=(--resource-group "${ACR_RESOURCE_GROUP}")
  else
    AZ_ACR_RESOURCE_ARGS=()
  fi

  _REGISTRY_INITIALIZED=1
}

registry_get_url() {
  registry__initialize
  echo "$ACR_LOGIN_SERVER"
}

registry_repository_ref() {
  local image=$1
  echo "$(registry_get_url)/${image}"
}

registry_repository() {
  registry_repository_ref "$1"
}

registry_login() {
  registry__initialize

  if command -v az >/dev/null 2>&1; then
    registry_require_command az
    az acr login --name "$ACR_NAME" >/dev/null
    return
  fi

  if [[ -n "${ACR_USERNAME:-}" && -n "${ACR_PASSWORD:-}" ]]; then
    registry_require_command docker
    printf '%s' "${ACR_PASSWORD}" | docker login "$ACR_LOGIN_SERVER" \
      --username "${ACR_USERNAME}" \
      --password-stdin >/dev/null
    return
  fi

  echo "Error: Unable to authenticate to Azure Container Registry. Install Azure CLI or provide ACR_USERNAME and ACR_PASSWORD." >&2
  exit 1
}

registry_manifest_digest() {
  registry__initialize
  registry_require_command az

  local repository=$1
  local tag=$2

  az acr repository show-manifests \
    --name "$ACR_NAME" \
    "${AZ_ACR_RESOURCE_ARGS[@]}" \
    --repository "$repository" \
    --query "[?tags && contains(tags, '${tag}')].digest | [0]" \
    --output tsv
}

registry_create_tag() {
  local repository=$1
  local source_tag=$2
  local target_tag=$3

  local digest
  digest=$(registry_manifest_digest "$repository" "$source_tag")
  if [[ -z "$digest" || "$digest" == "None" ]]; then
    echo "Error: unable to retrieve manifest digest for ${repository}:${source_tag}" >&2
    return 1
  fi

  registry_require_command az
  registry__initialize

  az acr manifest create \
    --registry "${ACR_NAME}" \
    "${AZ_ACR_RESOURCE_ARGS[@]}" \
    --name "${repository}:${target_tag}" \
    --image "${repository}@${digest}" \
    --force \
    >/dev/null
}
