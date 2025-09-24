#!/bin/bash

# This script builds and pushes the edge-endpoint Docker image to a container registry.
#
# Usage:
#   ./build-push-edge-endpoint-image.sh
#
# The script does the following:
# 1. Sets the image tag based on the current git commit.
# 2. Optionally authenticates Docker with the configured registry.
# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to the registry.
#
# Note: Ensure you have Docker installed. Provide registry credentials via
# REGISTRY_USERNAME/REGISTRY_PASSWORD (or REGISTRY_PASSWORD_FILE) if authentication is required.

set -euo pipefail

cd "$(dirname "$0")"

TAG=$(./git-tag-name.sh)
IMAGE_REPOSITORY=${IMAGE_REPOSITORY:-acrintellioptics.azurecr.io/intellioptics/edge-endpoint}
REGISTRY_SERVER=${REGISTRY_SERVER:-${IMAGE_REPOSITORY%%/*}}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-}
REGISTRY_PASSWORD_FILE=${REGISTRY_PASSWORD_FILE:-}

if [[ -z "$REGISTRY_PASSWORD" && -n "$REGISTRY_PASSWORD_FILE" ]]; then
  if [[ ! -f "$REGISTRY_PASSWORD_FILE" ]]; then
    echo "Registry password file '$REGISTRY_PASSWORD_FILE' not found" >&2
    exit 1
  fi
  REGISTRY_PASSWORD=$(<"$REGISTRY_PASSWORD_FILE")
fi

if [[ -n "$REGISTRY_USERNAME" && -n "$REGISTRY_PASSWORD" ]]; then
  echo "$REGISTRY_PASSWORD" | docker login \
                  --username "$REGISTRY_USERNAME" \
                  --password-stdin  "$REGISTRY_SERVER"
else
  echo "Registry credentials not provided; skipping docker login."
fi

if [[ "${1:-}" == "dev" ]]; then
  echo "'$0 dev' is no longer supported!!"
  exit 1
fi

# Install QEMU for multiplatform builds
docker run --rm --privileged linuxkit/binfmt:af88a591f9cc896a52ce596b9cf7ca26a061ef97

# Check if tempbuilder already exists
if ! docker buildx ls | grep -q tempgroundlightedgebuilder; then
  docker buildx create --name tempgroundlightedgebuilder --use
else
  docker buildx use tempgroundlightedgebuilder
fi

docker buildx inspect tempgroundlightedgebuilder --bootstrap

echo "Building and pushing $IMAGE_REPOSITORY:$TAG"
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --tag ${IMAGE_REPOSITORY}:${TAG} \
  ../.. --push

echo "Successfully pushed image to ${IMAGE_REPOSITORY}:${TAG}"
