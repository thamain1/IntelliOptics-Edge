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
        --output tsv
      ;;
  esac
}
