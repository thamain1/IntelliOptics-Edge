#!/bin/bash

# This script will build the edge-endpoint image and add it to the local k3s cluster
# for development and testing. If the image already exists in the k3s cluster, it will
# skip the upload step.
#
# It creates a single-platform image with the full registry-style name, but it always uses
# the 'dev' tag. When deploying application to your local test k3s cluster, add the
# following Helm value:
# `--set edgeEndpointTag=dev (or add it to your values.yaml file)

set -euo pipefail

REGISTRY_PROVIDER=${REGISTRY_PROVIDER:-aws}

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

cd "$(dirname "$0")"
source ./registry.sh

TAG=dev # In local mode, we always use the 'dev' tag
EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images
REGISTRY_URL=$(registry_get_url)

# The socket that's used by the k3s containerd
SOCK=/run/k3s/containerd/containerd.sock

project_root="$(readlink -f "../../")"

build_and_upload() {
    local name=$1
    local path=. # Edge endpoint is built from the root directory
    echo "Building and uploading ${name} to ${REGISTRY_URL} (provider=${REGISTRY_PROVIDER})..."
    cd "${project_root}/${path}"
    local repo=$(registry_repository_ref "${name}")
    local full_name=${repo}:${TAG}
    docker build -t ${full_name} .
    local id=$(docker image inspect ${full_name} | jq -r '.[0].Id')
    local on_server=$(sudo crictl images -q | grep $id || true)
    if [ -z "$on_server" ]; then
        echo "Image not found in k3s, uploading..."
        docker save ${full_name} | sudo ctr -a ${SOCK} -n k8s.io images import -
    else
        echo "Image exists in k3s, skipping upload."
    fi
}

build_and_upload "${EDGE_ENDPOINT_IMAGE}"
