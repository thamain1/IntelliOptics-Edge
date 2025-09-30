#!/bin/bash

# Build the edge-endpoint image locally and load it into the k3s cluster for testing.

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
registry_require_command jq

TAG=dev
EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}
REGISTRY_REF=$(registry_repository_ref "${EDGE_ENDPOINT_IMAGE}")
IMAGE_NAME="${REGISTRY_REF}:${TAG}"

PROJECT_ROOT="$(realpath "${SCRIPT_DIR}/../..")"
SOCK=/run/k3s/containerd/containerd.sock

cd "${PROJECT_ROOT}"

docker build -t "${IMAGE_NAME}" .

IMAGE_ID=$(docker image inspect "${IMAGE_NAME}" | jq -r '.[0].Id')
if ! sudo crictl images -q | grep -Fxq "${IMAGE_ID}"; then
  echo "Image not found in k3s, importing ${IMAGE_NAME}"
  docker save "${IMAGE_NAME}" | sudo ctr -a "${SOCK}" -n k8s.io images import -
else
  echo "Image already present in k3s, skipping import"
fi

echo "Local build complete: ${IMAGE_NAME}"
