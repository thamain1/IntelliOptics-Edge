#!/bin/bash

# This script builds and pushes the edge-endpoint Docker image to Azure
# Container Registry (ACR).
#
# Usage:
#   ./build-push-edge-endpoint-image.sh
#
# The script does the following:
# 1. Sets the image tag based on the current git commit.
# 2. Authenticates Docker with ACR (when credentials are provided).
# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to ACR.
#
# Note: Ensure you have Docker installed. Provide ACR credentials via the
# environment variables `ACR_LOGIN_SERVER`, `ACR_USERNAME`, and
# `ACR_PASSWORD`, or log in to the registry before running the script.

ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-acrintellioptics.azurecr.io}

set -e

# Ensure that you're in the same directory as this script before running it
cd "$(dirname "$0")"

TAG=$(./git-tag-name.sh)

EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-intellioptics/edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images
ACR_REPOSITORY="${ACR_LOGIN_SERVER}/${EDGE_ENDPOINT_IMAGE}"

# Authenticate docker to ACR when credentials are available. If credentials are
# not supplied we assume the user has already logged in (for example via
# `docker login`).
if [[ -n "${ACR_USERNAME:-}" && -n "${ACR_PASSWORD:-}" ]]; then
  echo "Logging in to ${ACR_LOGIN_SERVER}"
  echo "${ACR_PASSWORD}" | docker login \
    --username "${ACR_USERNAME}" \
    --password-stdin "${ACR_LOGIN_SERVER}"
else
  echo "ACR credentials not provided; assuming docker is already logged in to ${ACR_LOGIN_SERVER}."
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
  --tag ${ACR_REPOSITORY}:${TAG} \
  --tag ${ACR_REPOSITORY}:latest \
  ../.. --push

echo "Successfully pushed image to ${ACR_REPOSITORY}"
echo "${ACR_REPOSITORY}:${TAG}"


