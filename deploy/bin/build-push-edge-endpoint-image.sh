#!/bin/bash


# This script builds and pushes the edge-endpoint Docker image to Azure Container Registry (ACR).


# This script builds and pushes the edge-endpoint Docker image to Azure Container Registry (ACR).


# This script builds and pushes the edge-endpoint Docker image to a container registry.

# This script builds and pushes the edge-endpoint Docker image to Azure
# Container Registry (ACR).


# This script builds and pushes the edge-endpoint Docker image to Azure Container Registry (ACR).


# This script builds and pushes the edge-endpoint Docker image to a container
# registry that is not Amazon ECR.


# This script builds and pushes the edge-endpoint Docker image to a container
# registry that is not Amazon ECR.

# This script builds and pushes the edge-endpoint Docker image to Azure Container Registry (ACR).



#
# Usage:
#   REGISTRY_SERVER=ghcr.io REGISTRY_NAMESPACE=intellioptics \
#   REGISTRY_USERNAME=<user> REGISTRY_PASSWORD=<token> \
#     ./build-push-edge-endpoint-image.sh
#
# The script does the following:
# 1. Sets the image tag based on the current git commit.



# 2. Builds a multi-platform Docker image.
# 3. Pushes the image to the configured registry.
#
# Note: Ensure you have Docker installed and are logged in to the target
# container registry before running this script.

REGISTRY_LOGIN_SERVER=${REGISTRY_LOGIN_SERVER:-${CONTAINER_REGISTRY:-}}

if [ -z "$REGISTRY_LOGIN_SERVER" ]; then
  echo "REGISTRY_LOGIN_SERVER (or CONTAINER_REGISTRY) must be provided"
  exit 1
fi


# 2. Authenticates Docker with ACR (when credentials are provided).
# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to ACR.
#
# Note: Ensure you have Docker installed. Provide ACR credentials via the
# environment variables `ACR_LOGIN_SERVER`, `ACR_USERNAME`, and
# `ACR_PASSWORD`, or log in to the registry before running the script.

ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-acrintellioptics.azurecr.io}



# 2. Authenticates Docker with ACR.
# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to ACR.
#

# Note: Ensure you have the Azure CLI and Docker installed and that the
# service principal or CLI session has access to the target registry.

ACR_NAME=${ACR_NAME:-acrintellioptics}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-${ACR_NAME}.azurecr.io}

# Note: Ensure you have the necessary Azure credentials and Docker installed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib-azure-acr-login.sh"

# 2. Authenticates Docker with the target registry when credentials are provided.

# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to the configured registry.


# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to the configured registry.

# 2. Authenticates Docker with ACR.
# 3. Builds a multi-platform Docker image.
# 4. Pushes the image to ACR.
#

# Note: Ensure you have authenticated to Azure and have Docker installed.

ACR_NAME=${ACR_NAME:-acrintellioptics}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-${ACR_NAME}.azurecr.io}
ACR_REPOSITORY=${ACR_REPOSITORY:-intellioptics/edge-endpoint}


# Note: Ensure you have the necessary Azure credentials (e.g., via `az login`) and Docker installed.


ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-acrintellioptics.azurecr.io}
ACR_REGISTRY_NAME=${ACR_REGISTRY_NAME:-${ACR_LOGIN_SERVER%%.*}}



# Note: Ensure you have the necessary Azure credentials and Docker installed.

ACR_NAME=${ACR_NAME:-intelliopticsedge}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-${ACR_NAME}.azurecr.io}


set -euo pipefail

# Ensure that you're in the same directory as this script before running it
cd "${SCRIPT_DIR}"

TAG=$(./git-tag-name.sh)

EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-${ACR_REPOSITORY}}  # Default to intellioptics/edge-endpoint images
ACR_IMAGE_TAG="${ACR_LOGIN_SERVER}/${EDGE_ENDPOINT_IMAGE}:${TAG}"

# Authenticate docker to ACR. Prefer Azure CLI when available and logged in.
if command -v az >/dev/null 2>&1; then
  if [ -n "${ACR_NAME}" ]; then
    echo "Logging into Azure Container Registry '${ACR_NAME}' via Azure CLI"
    az acr login --name "${ACR_NAME}"
  else
    echo "ACR_NAME must be set when using az acr login" >&2
    exit 1
  fi
elif [ -n "${ACR_USERNAME:-}" ] && [ -n "${ACR_PASSWORD:-}" ]; then
  echo "Logging into Azure Container Registry '${ACR_LOGIN_SERVER}' via docker login"

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

  echo "Unable to authenticate to Azure Container Registry. Install Azure CLI or provide ACR_USERNAME/ACR_PASSWORD." >&2
  exit 1
fi
  echo "ACR credentials not provided; assuming docker is already logged in to ${ACR_LOGIN_SERVER}."
fi

REGISTRY_SERVER=${REGISTRY_SERVER:-}
REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE:-}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-}
EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images

if ! command -v az >/dev/null 2>&1; then
  echo "The Azure CLI (az) is required to push to ACR." >&2
  exit 1
fi

echo "Authenticating Docker with Azure Container Registry ${ACR_NAME}."
az acr login --name "${ACR_NAME}" >/dev/null

REGISTRY_IMAGE="${REGISTRY_LOGIN_SERVER}/${EDGE_ENDPOINT_IMAGE}"


ACR_URL="${ACR_LOGIN_SERVER}"

# Authenticate docker to ACR
azure_acr_login "$ACR_URL" "$ACR_REGISTRY_NAME"



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

ACR_URL="${ACR_LOGIN_SERVER}"

if ! command -v az >/dev/null 2>&1; then
  echo "Error: Azure CLI (az) is required but not installed." >&2
  exit 1
fi

echo "Logging into Azure Container Registry '${ACR_REGISTRY_NAME}' (${ACR_URL})"
az acr login --name "${ACR_REGISTRY_NAME}"

ACR_REGISTRY="${ACR_LOGIN_SERVER}"

# Authenticate docker to ACR
echo "Authenticating Docker with Azure Container Registry '${ACR_NAME}'"
if ! az acr login --name "${ACR_NAME}"; then
  echo "'az acr login' failed; attempting docker login using admin credentials"
  ACR_USERNAME=${ACR_USERNAME:-$(az acr credential show --name "${ACR_NAME}" --query "username" -o tsv)}
  ACR_PASSWORD=${ACR_PASSWORD:-$(az acr credential show --name "${ACR_NAME}" --query "passwords[0].value" -o tsv)}
  echo "${ACR_PASSWORD}" | docker login "${ACR_REGISTRY}" --username "${ACR_USERNAME}" --password-stdin
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

  --tag "${ACR_IMAGE_TAG}" \
  ../.. --push

echo "Successfully pushed image to ACR ${ACR_LOGIN_SERVER}"
echo "${ACR_IMAGE_TAG}"

  --tag ${ACR_LOGIN_SERVER}/${EDGE_ENDPOINT_IMAGE}:${TAG} \
  ../.. --push

echo "Successfully pushed image to ${ACR_LOGIN_SERVER}"
echo "${ACR_LOGIN_SERVER}/${EDGE_ENDPOINT_IMAGE}:${TAG}"


  --tag ${REGISTRY_IMAGE}:${TAG} \
  ../.. --push

echo "Successfully pushed image to ${REGISTRY_IMAGE}"
echo "${REGISTRY_IMAGE}:${TAG}"

  --tag ${ACR_REPOSITORY}:${TAG} \
  --tag ${ACR_REPOSITORY}:latest \
  ../.. --push

echo "Successfully pushed image to ${ACR_REPOSITORY}"
echo "${ACR_REPOSITORY}:${TAG}"

  --tag ${ACR_URL}/${EDGE_ENDPOINT_IMAGE}:${TAG} \
  ../.. --push

echo "Successfully pushed image to ACR_URL=${ACR_URL}"
echo "${ACR_URL}/${EDGE_ENDPOINT_IMAGE}:${TAG}"

  --tag ${IMAGE_REPOSITORY}:${TAG} \
  ../.. --push

echo "Successfully pushed image to ${IMAGE_REPOSITORY}"
echo "${IMAGE_REPOSITORY}:${TAG}"


  --tag ${ACR_URL}/${EDGE_ENDPOINT_IMAGE}:${TAG} \
  ../.. --push

echo "Successfully pushed image to ACR_URL=${ACR_URL}"
echo "${ACR_URL}/${EDGE_ENDPOINT_IMAGE}:${TAG}"

  --tag ${ACR_REGISTRY}/${EDGE_ENDPOINT_IMAGE}:${TAG} \
  ../.. --push

echo "Successfully pushed image to ACR_REGISTRY=${ACR_REGISTRY}"
echo "${ACR_REGISTRY}/${EDGE_ENDPOINT_IMAGE}:${TAG}"



