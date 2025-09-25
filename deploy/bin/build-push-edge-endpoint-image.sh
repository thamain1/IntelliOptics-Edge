#!/bin/bash

# This script builds and pushes the edge-endpoint Docker image to Azure Container Registry (ACR).
#
# Usage:
#   ./build-push-edge-endpoint-image.sh
#
# The script does the following:
# 1. Sets the image tag based on the current git commit.
# 2. Authenticates Docker with ACR.
# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to ACR.
#
# Note: Ensure you have the Azure CLI, Docker, and access to the target ACR instance.

set -e

# Ensure that you're in the same directory as this script before running it
cd "$(dirname "$0")"

AZURE_ACR_NAME=${AZURE_ACR_NAME:-intellioptics}
AZURE_ACR_LOGIN_SERVER=${AZURE_ACR_LOGIN_SERVER:-${AZURE_ACR_NAME}.azurecr.io}
TAG=$(./git-tag-name.sh)

EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images

if [ "$1" == "dev" ]; then
  echo "'$0 dev' is no longer supported!!"
  exit 1
fi

# Authenticate docker to ACR. Prefer Azure CLI if available, otherwise rely on provided credentials.
if command -v az >/dev/null 2>&1; then
  az acr login --name "${AZURE_ACR_NAME}"
elif [[ -n "${AZURE_ACR_USERNAME:-}" && -n "${AZURE_ACR_PASSWORD:-}" ]]; then
  echo "${AZURE_ACR_PASSWORD}" | docker login \
    --username "${AZURE_ACR_USERNAME}" \
    --password-stdin "${AZURE_ACR_LOGIN_SERVER}"
else
  echo "Unable to authenticate to Azure Container Registry. Install the Azure CLI or provide AZURE_ACR_USERNAME and AZURE_ACR_PASSWORD." >&2
  exit 1
fi

# We use docker buildx to build the image for multiple platforms. buildx comes
# installed with Docker Engine when installed via Docker Desktop. If you're
# on a Linux machine with an old version of Docker Engine, you may need to
# install buildx manually. Follow these instructions to install docker-buildx-plugin:
# https://docs.docker.com/engine/install/ubuntu/

# Install QEMU, a generic and open-source machine emulator and virtualizer
docker run --rm --privileged linuxkit/binfmt:af88a591f9cc896a52ce596b9cf7ca26a061ef97

# Check if tempbuilder already exists
if ! docker buildx ls | grep -q tempgroundlightedgebuilder; then
  # Prep for multiplatform build - the build is done INSIDE a docker container
  docker buildx create --name tempgroundlightedgebuilder --use
else
  # If tempbuilder exists, set it as the current builder
  docker buildx use tempgroundlightedgebuilder
fi

# Ensure that the tempbuilder container is running
docker buildx inspect tempgroundlightedgebuilder --bootstrap

# Build image for amd64 and arm64
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --tag ${AZURE_ACR_LOGIN_SERVER}/${EDGE_ENDPOINT_IMAGE}:${TAG} \
  ../.. --push

echo "Successfully pushed image to ${AZURE_ACR_LOGIN_SERVER}"
echo "${AZURE_ACR_LOGIN_SERVER}/${EDGE_ENDPOINT_IMAGE}:${TAG}"
