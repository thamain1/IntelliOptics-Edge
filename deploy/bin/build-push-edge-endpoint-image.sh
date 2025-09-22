#!/bin/bash

# This script builds and pushes the edge-endpoint Docker image to ECR.
#
# Usage:
#   ./build-push-edge-endpoint-image.sh
#
# The script does the following:
# 1. Sets the image tag based on the current git commit.
# 2. Authenticates Docker with ECR.
# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to ECR.
#
# Note: Ensure you have the necessary AWS credentials and Docker installed.

set -e

# Ensure that you're in the same directory as this script before running it
cd "$(dirname "$0")"

TAG=$(./git-tag-name.sh)

EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images
REGISTRY_LOGIN_SERVER=""

if [ -n "${ACR_LOGIN_SERVER:-}" ]; then
  REGISTRY_LOGIN_SERVER="${ACR_LOGIN_SERVER}"
  ACR_NAME=${ACR_NAME:-${REGISTRY_LOGIN_SERVER%%.*}}
  echo "🔐 Logging into Azure Container Registry '${ACR_NAME}'"
  az acr login --name "${ACR_NAME}"
else
  ECR_ACCOUNT=${ECR_ACCOUNT:-767397850842}
  ECR_REGION=${ECR_REGION:-us-west-2}
  ECR_URL="${ECR_ACCOUNT}.dkr.ecr.${ECR_REGION}.amazonaws.com"
  REGISTRY_LOGIN_SERVER="${ECR_URL}"

  # Authenticate docker to ECR
  aws ecr get-login-password --region ${ECR_REGION} | docker login \
                    --username AWS \
                    --password-stdin  ${ECR_URL}
fi

REGISTRY_IMAGE="${REGISTRY_LOGIN_SERVER}/${EDGE_ENDPOINT_IMAGE}"

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
  --tag ${REGISTRY_IMAGE}:${TAG} \
  ../.. --push

echo "Successfully pushed image to registry=${REGISTRY_LOGIN_SERVER}"
echo "${REGISTRY_IMAGE}:${TAG}"


