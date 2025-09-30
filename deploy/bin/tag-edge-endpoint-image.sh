#!/bin/bash

# Create an additional tag for an existing edge-endpoint image in Azure Container Registry.

set -euo pipefail

REGISTRY_PROVIDER=${REGISTRY_PROVIDER:-azure}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry-provider)
      REGISTRY_PROVIDER=$(echo "$2" | tr '[:upper:]' '[:lower:]')
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ "$REGISTRY_PROVIDER" != "azure" ]]; then
  echo "Error: only the Azure registry workflow is supported. Set REGISTRY_PROVIDER=azure." >&2
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [--registry-provider azure] <new-tag>" >&2
  exit 1
fi

NEW_TAG=$1

if [[ "$NEW_TAG" == "pre-release" || "$NEW_TAG" == "release" || "$NEW_TAG" == "latest" ]]; then
  if [[ -z "${GITHUB_ACTIONS:-}" ]]; then
    echo "Error: The tag '$NEW_TAG' can only be created from GitHub Actions." >&2
    exit 1
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

# shellcheck disable=SC1091
source ./registry.sh

EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}
GIT_TAG=$(./git-tag-name.sh)

REGISTRY_URL=$(registry_get_url)
REPOSITORY_REF=$(registry_repository_ref "${EDGE_ENDPOINT_IMAGE}")

registry_login

registry_create_tag "${EDGE_ENDPOINT_IMAGE}" "${GIT_TAG}" "${NEW_TAG}"

echo "Tag '${NEW_TAG}' created for ${REPOSITORY_REF}:${GIT_TAG}"
