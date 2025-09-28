#!/bin/bash




# Put a specific tag on an existing image in the configured container
# registry. This script no longer depends on AWS ECR tooling.

set -euo pipefail


# Put a specific tag on an existing image in the configured container
# registry. This script no longer depends on AWS ECR tooling.

set -euo pipefail


# Put a specific tag on an existing image in Azure Container Registry (ACR)
# Assumptions:
# - The image is already built and pushed to ACR
# - The image is tagged with the git commit hash

set -e  # Exit immediately on error
set -o pipefail


ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-acrintellioptics.azurecr.io}


# shellcheck disable=SC1091
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib-azure-acr-login.sh"

ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-acrintellioptics.azurecr.io}
ACR_REGISTRY_NAME=${ACR_REGISTRY_NAME:-${ACR_LOGIN_SERVER%%.*}}
=======
ACR_NAME=${ACR_NAME:-intelliopticsedge}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-${ACR_NAME}.azurecr.io}




# Ensure that you're in the same directory as this script before running it
cd "${SCRIPT_DIR}"

# Check if an argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <new-tag>"
    exit 1
fi

NEW_TAG=$1

# Only the pipeline can create releases
if [[ "$NEW_TAG" == "pre-release" || "$NEW_TAG" == "release" || "$NEW_TAG" == "latest" ]]; then
    if [ -z "$GITHUB_ACTIONS" ]; then
        echo "Error: The tag '$NEW_TAG' can only be used inside GitHub Actions."
        exit 1
    fi
fi

GIT_TAG=$(./git-tag-name.sh)

EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-intellioptics/edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images
ACR_REPO="${ACR_LOGIN_SERVER}/${EDGE_ENDPOINT_IMAGE}"

# Authenticate docker to ACR when credentials are available. If credentials are
# not supplied we assume the user has already logged in.
if [[ -n "${ACR_USERNAME:-}" && -n "${ACR_PASSWORD:-}" ]]; then
    echo "Logging in to ${ACR_LOGIN_SERVER}"
    echo "${ACR_PASSWORD}" | docker login \
        --username "${ACR_USERNAME}" \
        --password-stdin "${ACR_LOGIN_SERVER}"
else
    echo "ACR credentials not provided; assuming docker is already logged in to ${ACR_LOGIN_SERVER}."
fi
EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images
ACR_URL="${ACR_LOGIN_SERVER}"
ACR_REPO="${ACR_URL}/${EDGE_ENDPOINT_IMAGE}"

# Authenticate docker to ACR
azure_acr_login "$ACR_URL" "$ACR_REGISTRY_NAME"
REGISTRY_SERVER=${REGISTRY_SERVER:-}
REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE:-}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-}

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
ACR_REPO="${ACR_URL}/${EDGE_ENDPOINT_IMAGE}"

if ! command -v az >/dev/null 2>&1; then
    echo "Error: Azure CLI (az) is required but not installed." >&2
    exit 1
fi

echo "Logging into Azure Container Registry '${ACR_REGISTRY_NAME}' (${ACR_URL})"
az acr login --name "${ACR_REGISTRY_NAME}"

ACR_REGISTRY="${ACR_LOGIN_SERVER}"
ACR_REPO="${ACR_REGISTRY}/${EDGE_ENDPOINT_IMAGE}"

# Authenticate docker to ACR
echo "Authenticating Docker with Azure Container Registry '${ACR_NAME}'"
if ! az acr login --name "${ACR_NAME}"; then
  echo "'az acr login' failed; attempting docker login using admin credentials"
  ACR_USERNAME=${ACR_USERNAME:-$(az acr credential show --name "${ACR_NAME}" --query "username" -o tsv)}
  ACR_PASSWORD=${ACR_PASSWORD:-$(az acr credential show --name "${ACR_NAME}" --query "passwords[0].value" -o tsv)}
  echo "${ACR_PASSWORD}" | docker login "${ACR_REGISTRY}" --username "${ACR_USERNAME}" --password-stdin
fi



# Tag the image with the new tag
# To do this, we need to pull the digest SHA of the existing multiplatform image
# and then create the tag on that SHA. Otherwise imagetools will create a tag for
# just the platform where the command is run.

echo "🏷️ Tagging image $ACR_REPO:$GIT_TAG with tag $NEW_TAG"
digest=$(docker buildx imagetools inspect $ACR_REPO:$GIT_TAG --format '{{json .}}' | jq -r .manifest.digest)
docker buildx imagetools create --tag $ACR_REPO:$NEW_TAG $ACR_REPO@${digest}

echo "✅ Image successfully tagged: $ACR_REPO:$NEW_TAG"

echo "🏷️ Tagging image $ACR_REPO:$GIT_TAG with tag $NEW_TAG"
digest=$(docker buildx imagetools inspect $ACR_REPO:$GIT_TAG --format '{{json .}}' | jq -r .manifest.digest)
docker buildx imagetools create --tag $ACR_REPO:$NEW_TAG $ACR_REPO@${digest}

echo "✅ Image successfully tagged: $ACR_REPO:$NEW_TAG"
echo "🏷️ Tagging image $IMAGE_REPOSITORY:$GIT_TAG with tag $NEW_TAG"
digest=$(docker buildx imagetools inspect $IMAGE_REPOSITORY:$GIT_TAG --format '{{json .}}' | jq -r .manifest.digest)
docker buildx imagetools create --tag $IMAGE_REPOSITORY:$NEW_TAG $IMAGE_REPOSITORY@${digest}


echo "✅ Image successfully tagged: $IMAGE_REPOSITORY:$NEW_TAG"

echo "✅ Image successfully tagged: $IMAGE_REPOSITORY:$NEW_TAG"
echo "🏷️ Tagging image $ACR_REPO:$GIT_TAG with tag $NEW_TAG"
digest=$(docker buildx imagetools inspect $ACR_REPO:$GIT_TAG --format '{{json .}}' | jq -r .manifest.digest)
docker buildx imagetools create --tag $ACR_REPO:$NEW_TAG $ACR_REPO@${digest}
echo "✅ Image successfully tagged: $ACR_REPO:$NEW_TAG"



