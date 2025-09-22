#!/bin/bash

# This script builds and pushes the edge-endpoint Docker image to Azure
# Container Registry (ACR).
#
# Usage:
#   ./build-push-edge-endpoint-image.sh
#
# The script does the following:
# 1. Sets the image tag based on the current git commit.
# 2. Authenticates Docker with Azure Container Registry.
# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to Azure Container Registry.
#
# Note: Ensure you have the necessary Azure credentials and Docker installed.

ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-intelliopticsedge.azurecr.io}
ACR_USERNAME=${ACR_USERNAME:-}
ACR_PASSWORD=${ACR_PASSWORD:-}
ACR_NAME=${ACR_NAME:-}

set -e

# Ensure that you're in the same directory as this script before running it
cd "$(dirname "$0")"

TAG=$(./git-tag-name.sh)

EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images
ACR_REPOSITORY=${ACR_REPOSITORY:-${EDGE_ENDPOINT_IMAGE}}

if [ -z "${ACR_LOGIN_SERVER}" ]; then
  echo "Error: ACR_LOGIN_SERVER must be set."
  exit 1
fi

ACR_SERVER_HOST=${ACR_LOGIN_SERVER%%:*}

# Authenticate docker to ACR
if command -v az >/dev/null 2>&1; then
  ACR_NAME=${ACR_NAME:-${ACR_SERVER_HOST%%.azurecr.io}}
  if [ -z "${ACR_NAME}" ]; then
    echo "Error: Unable to determine ACR name for az login. Set ACR_NAME explicitly."
    exit 1
  fi
  echo "🔐 Logging into Azure Container Registry '${ACR_NAME}' via az CLI"
  az acr login --name "${ACR_NAME}"
elif [ -n "${ACR_USERNAME}" ] && [ -n "${ACR_PASSWORD}" ]; then
  echo "🔐 Logging into Azure Container Registry '${ACR_LOGIN_SERVER}' via docker login"
  echo "${ACR_PASSWORD}" | docker login "${ACR_LOGIN_SERVER}" \
    --username "${ACR_USERNAME}" \
    --password-stdin
else
  echo "Error: Unable to authenticate to ACR. Provide az CLI or set ACR_USERNAME and ACR_PASSWORD."
  exit 1
fi

if [ "$1" == "dev" ]; then
  echo "'$0 dev' is no longer supported!!"
  exit 1
fi

# We use docker buildx to build the image for multiple platforms. buildx comes
# installed with Docker Engine when installed via Docker Desktop. If you're
# on a Linux machine with an old version of Docker Engine, you may need to
# install buildx manually. Follow these instructions to install docker-buildx-plugin:
# https://docs.docker.com/engine/install/ubuntu/

# Install QEMU, a generic and open-source machine emulator and virtualizer
docker run --rm --privileged linuxkit/binfmt:af88a591f9cc896a52ce596b9cf7ca26a061ef97

# Check if IntelliOptics buildx builder already exists
if ! docker buildx ls | grep -q intellioptics-edge-builder; then
  # Prep for multiplatform build - the build is done INSIDE a docker container
  docker buildx create --name intellioptics-edge-builder --use
else
  # If the IntelliOptics builder exists, set it as the current builder
  docker buildx use intellioptics-edge-builder
fi

# Ensure that the IntelliOptics buildx container is running
docker buildx inspect intellioptics-edge-builder --bootstrap

# Build image for amd64 and arm64
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --tag ${ACR_LOGIN_SERVER}/${ACR_REPOSITORY}:${TAG} \
  ../.. --push

echo "Successfully pushed image to ACR registry=${ACR_LOGIN_SERVER}"
echo "${ACR_LOGIN_SERVER}/${ACR_REPOSITORY}:${TAG}"


