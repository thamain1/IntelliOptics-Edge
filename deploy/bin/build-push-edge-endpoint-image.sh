#!/bin/bash

# This script builds and pushes the edge-endpoint Docker image to a container
# registry that is not Amazon ECR.
#
# Usage:
#   REGISTRY_SERVER=ghcr.io REGISTRY_NAMESPACE=intellioptics \
#   REGISTRY_USERNAME=<user> REGISTRY_PASSWORD=<token> \
#     ./build-push-edge-endpoint-image.sh
#
# The script does the following:
# 1. Sets the image tag based on the current git commit.
# 2. Authenticates Docker with the target registry when credentials are provided.
# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to the configured registry.

set -euo pipefail

# Ensure that you're in the same directory as this script before running it
cd "$(dirname "$0")"

TAG=$(./git-tag-name.sh)

REGISTRY_SERVER=${REGISTRY_SERVER:-}
REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE:-}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-}
EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images

if [[ -z "${REGISTRY_SERVER}" ]]; then
  echo "Error: REGISTRY_SERVER must be set (for example, ghcr.io)." >&2
  exit 1
fi

IMAGE_REPOSITORY="${REGISTRY_SERVER}/"
if [[ -n "${REGISTRY_NAMESPACE}" ]]; then
  IMAGE_REPOSITORY+="${REGISTRY_NAMESPACE}/"
fi
IMAGE_REPOSITORY+="${EDGE_ENDPOINT_IMAGE}"

if [[ -n "${REGISTRY_USERNAME}" && -n "${REGISTRY_PASSWORD}" ]]; then
  echo "Logging in to ${REGISTRY_SERVER} as ${REGISTRY_USERNAME}" >&2
  echo "${REGISTRY_PASSWORD}" | docker login "${REGISTRY_SERVER}" --username "${REGISTRY_USERNAME}" --password-stdin
else
  echo "Skipping registry login because REGISTRY_USERNAME or REGISTRY_PASSWORD is not set." >&2
  echo "Ensure you are already logged in via 'docker login ${REGISTRY_SERVER}'." >&2
fi

if [[ ${1:-} == "dev" ]]; then
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
  --tag ${IMAGE_REPOSITORY}:${TAG} \
  ../.. --push

echo "Successfully pushed image to ${IMAGE_REPOSITORY}"
echo "${IMAGE_REPOSITORY}:${TAG}"


