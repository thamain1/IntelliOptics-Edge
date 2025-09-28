#!/bin/bash

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
