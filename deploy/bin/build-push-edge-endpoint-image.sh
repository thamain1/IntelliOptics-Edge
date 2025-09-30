#!/bin/bash

# Build and push the edge-endpoint Docker image to Azure Container Registry (ACR).

set -euo pipefail

REGISTRY_PROVIDER=${REGISTRY_PROVIDER:-azure}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry-provider)
      REGISTRY_PROVIDER=$(echo "$2" | tr '[:upper:]' '[:lower:]')
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$REGISTRY_PROVIDER" != "azure" ]]; then
  echo "Error: only the Azure registry workflow is supported. Set REGISTRY_PROVIDER=azure." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

# shellcheck disable=SC1091
source ./registry.sh

registry_require_command docker

TAG=$(./git-tag-name.sh)
EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}

REGISTRY_URL=$(registry_get_url)
REPOSITORY_REF=$(registry_repository_ref "${EDGE_ENDPOINT_IMAGE}")

registry_login

# Ensure the buildx builder exists for multi-platform builds.
docker run --rm --privileged linuxkit/binfmt:af88a591f9cc896a52ce596b9cf7ca26a061ef97

if ! docker buildx ls | grep -q tempgroundlightedgebuilder; then
  docker buildx create --name tempgroundlightedgebuilder --use
else
  docker buildx use tempgroundlightedgebuilder
fi

docker buildx inspect tempgroundlightedgebuilder --bootstrap

docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --tag "${REPOSITORY_REF}:${TAG}" \
  ../.. --push

echo "Successfully pushed image to ${REPOSITORY_REF}:${TAG}"
