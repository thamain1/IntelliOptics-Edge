#!/bin/bash

# This script builds and pushes the edge-endpoint Docker image to a container registry.
#
# Usage:
#   ./build-push-edge-endpoint-image.sh [--registry-provider aws|azure]
#
# The script does the following:
# 1. Sets the image tag based on the current git commit.
# 2. Authenticates Docker with the registry provider.
# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to the registry.
#
# Note: Ensure you have the necessary credentials and Docker installed.

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

# Ensure that you're in the same directory as this script before running it
cd "$(dirname "$0")"

source ./registry.sh

TAG=$(./git-tag-name.sh)
EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images
REGISTRY_URL=$(registry_get_url)
REPOSITORY_REF=$(registry_repository_ref "${EDGE_ENDPOINT_IMAGE}")

registry_login

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
  --tag ${REPOSITORY_REF}:${TAG} \
  ../.. --push

echo "Successfully pushed image to REGISTRY_URL=${REGISTRY_URL} (provider=${REGISTRY_PROVIDER})"
echo "${REPOSITORY_REF}:${TAG}"
