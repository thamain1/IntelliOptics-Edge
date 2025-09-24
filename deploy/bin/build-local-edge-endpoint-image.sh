#!/bin/bash

# This script will build the edge-endpoint image and add it to the local k3s cluster
# for development and testing. If the image already exists in the k3s cluster, it will
# skip the upload step.
#
# It creates a single-platform image using the configured repository name but always
# tags the image with "dev". When deploying to your local test k3s cluster, add the
# following Helm value:
# `--set edgeEndpointTag=dev` (or add it to your values.yaml file)

set -euo pipefail

cd "$(dirname "$0")"

TAG=${TAG:-dev}
IMAGE_REPOSITORY=${IMAGE_REPOSITORY:-acrintellioptics.azurecr.io/intellioptics/edge-endpoint}

# The socket that's used by the k3s containerd
SOCK=/run/k3s/containerd/containerd.sock

project_root="$(readlink -f "../../")"

build_and_upload() {
    local name=$1
    local path=. # Edge endpoint is built from the root directory
    echo "Building and uploading ${name}..."
    cd "${project_root}/${path}"
    local full_name=${name}:${TAG}
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

build_and_upload "${IMAGE_REPOSITORY}"
