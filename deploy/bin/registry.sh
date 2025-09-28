#!/bin/bash

set -euo pipefail

REGISTRY_PROVIDER=${REGISTRY_PROVIDER:-aws}
REGISTRY_PROVIDER=$(echo "${REGISTRY_PROVIDER}" | tr '[:upper:]' '[:lower:]')

registry_require_command() {
  local cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found" >&2
    exit 1
  fi
}

registry_provider() {
  echo "${REGISTRY_PROVIDER}"
}

registry_get_aws_account() {
  echo "${ECR_ACCOUNT:-767397850842}"
}

registry_get_aws_region() {
  echo "${ECR_REGION:-us-west-2}"
}

registry_get_acr_login_server() {
  local login_server="${ACR_LOGIN_SERVER:-}"
  local name="${ACR_NAME:-}"
  if [[ -z "$login_server" && -n "$name" ]]; then
    login_server="${name}.azurecr.io"
  fi
  if [[ -n "$login_server" && -z "$name" ]]; then
    name="${login_server%%.*}"
  fi
  if [[ -z "$login_server" ]]; then
    echo "Error: ACR_LOGIN_SERVER or ACR_NAME must be set for Azure registry usage" >&2
    exit 1
  fi
  ACR_NAME=${name:-${ACR_NAME:-}}
  echo "$login_server"
}

registry_get_url() {
  case "$(registry_provider)" in
    aws)
      local account=$(registry_get_aws_account)
      local region=$(registry_get_aws_region)
      echo "${account}.dkr.ecr.${region}.amazonaws.com"
      ;;
    azure)
      registry_get_acr_login_server
      ;;
    *)
      echo "Error: Unsupported REGISTRY_PROVIDER '$(registry_provider)'" >&2
      exit 1
      ;;
  esac
}

registry_repository_ref() {
  local image=$1
  echo "$(registry_get_url)/${image}"
}

registry_login() {
  case "$(registry_provider)" in
    aws)
      registry_require_command aws
      registry_require_command docker
      local region=$(registry_get_aws_region)
      local url=$(registry_get_url)
      aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$url"
      ;;
    azure)
      registry_require_command az
      registry_require_command docker
      registry_get_acr_login_server >/dev/null
      az acr login --name "$ACR_NAME" >/dev/null
# Shared registry helper functions for edge endpoint build and tag scripts.
# Supports AWS Elastic Container Registry and Azure Container Registry.

if [[ -z "${REGISTRY_PROVIDER:-}" ]]; then
  REGISTRY_PROVIDER=aws
fi

REGISTRY_PROVIDER=$(echo "$REGISTRY_PROVIDER" | tr '[:upper:]' '[:lower:]')

case "$REGISTRY_PROVIDER" in
  aws)
    ECR_ACCOUNT=${ECR_ACCOUNT:-767397850842}
    ECR_REGION=${ECR_REGION:-us-west-2}
    REGISTRY_URL="${ECR_ACCOUNT}.dkr.ecr.${ECR_REGION}.amazonaws.com"
    ;;
  azure)
    if [[ -z "${ACR_LOGIN_SERVER:-}" ]]; then
      if [[ -n "${ACR_NAME:-}" ]]; then
        ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
      else
        echo "Error: set either ACR_LOGIN_SERVER or ACR_NAME when REGISTRY_PROVIDER=azure" >&2
        exit 1
      fi
    fi
    if [[ -z "${ACR_NAME:-}" ]]; then
      # Derive ACR_NAME from login server (first label before '.')
      ACR_NAME=${ACR_LOGIN_SERVER%%.*}
    fi
    REGISTRY_URL="${ACR_LOGIN_SERVER}"
    AZ_ACR_RESOURCE_ARGS=()
    if [[ -n "${ACR_RESOURCE_GROUP:-}" ]]; then
      AZ_ACR_RESOURCE_ARGS=(--resource-group "${ACR_RESOURCE_GROUP}")
    fi
    ;;
  *)
    echo "Error: unsupported REGISTRY_PROVIDER '$REGISTRY_PROVIDER'. Supported providers: aws, azure" >&2
    exit 1
    ;;
 esac

registry_url() {
  echo "$REGISTRY_URL"
}

registry_repository() {
  local repository=$1
  echo "$(registry_url)/${repository}"
}

registry_login() {
  case "$REGISTRY_PROVIDER" in
    aws)
      aws ecr get-login-password --region "${ECR_REGION}" | docker login \
        --username AWS \
        --password-stdin "${REGISTRY_URL}"
      ;;
    azure)
      az acr login --name "${ACR_NAME}"
      ;;
  esac
}

registry_manifest_digest() {

  local image=$1
  local tag=$2
  case "$(registry_provider)" in
    aws)
      registry_require_command aws
      local region=$(registry_get_aws_region)
      local account=$(registry_get_aws_account)
      aws ecr describe-images \
        --region "$region" \
        --registry-id "$account" \
        --repository-name "$image" \
  local repository=$1
  local tag=$2
  case "$REGISTRY_PROVIDER" in
    aws)
      aws ecr describe-images \
        --repository-name "$repository" \
        --image-ids imageTag="$tag" \
        --query 'imageDetails[0].imageDigest' \
        --output text
      ;;
    azure)
      registry_require_command az
      registry_get_acr_login_server >/dev/null
      az acr repository show-manifests \
        --name "$ACR_NAME" \
        --repository "$image" \
        --query "[?tags && contains(join(' ', tags), '${tag}')].digest | [0]" \
      az acr repository show-manifests \
        --name "${ACR_NAME}" \
        "${AZ_ACR_RESOURCE_ARGS[@]}" \
        --repository "$repository" \
        --query "[?tags && contains(tags, '${tag}')].digest | [0]" \
        --output tsv
      ;;
  esac
}

registry_create_tag() {
  local repository=$1
  local source_tag=$2
  local target_tag=$3
  case "$REGISTRY_PROVIDER" in
    aws)
      local manifest
      manifest=$(aws ecr batch-get-image \
        --repository-name "$repository" \
        --image-ids imageTag="$source_tag" \
        --query 'images[0].imageManifest' \
        --output text)
      if [[ -z "$manifest" ]]; then
        echo "Error: unable to retrieve manifest for $repository:$source_tag" >&2
        return 1
      fi
      aws ecr put-image \
        --repository-name "$repository" \
        --image-tag "$target_tag" \
        --image-manifest "$manifest" \
        >/dev/null
      ;;
    azure)
      local digest
      digest=$(registry_manifest_digest "$repository" "$source_tag")
      if [[ -z "$digest" ]]; then
        echo "Error: unable to retrieve manifest digest for $repository:$source_tag" >&2
        return 1
      fi
      az acr manifest create \
        --registry "${ACR_NAME}" \
        "${AZ_ACR_RESOURCE_ARGS[@]}" \
        --name "${repository}:${target_tag}" \
        --image "${repository}@${digest}" \
        --force \
        >/dev/null
      ;;
  esac
}
