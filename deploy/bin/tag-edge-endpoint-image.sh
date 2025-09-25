#!/bin/bash

# Put a specific tag on an existing image in Azure Container Registry (ACR)
# Assumptions:
# - The image is already built and pushed to ACR
# - The image is tagged with the git commit hash

set -e  # Exit immediately on error
set -o pipefail

AZURE_ACR_NAME=${AZURE_ACR_NAME:-intellioptics}
AZURE_ACR_LOGIN_SERVER=${AZURE_ACR_LOGIN_SERVER:-${AZURE_ACR_NAME}.azurecr.io}

# Ensure that you're in the same directory as this script before running it
cd "$(dirname "$0")"

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
EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images
ACR_REPO="${AZURE_ACR_LOGIN_SERVER}/${EDGE_ENDPOINT_IMAGE}"

# Authenticate docker to ACR
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

# Tag the image with the new tag
# To do this, we need to pull the digest SHA of the existing multiplatform image
# and then create the tag on that SHA. Otherwise imagetools will create a tag for
# just the platform where the command is run.
echo "🏷️ Tagging image $ACR_REPO:$GIT_TAG with tag $NEW_TAG"
digest=$(docker buildx imagetools inspect $ACR_REPO:$GIT_TAG --format '{{json .}}' | jq -r .manifest.digest)
docker buildx imagetools create --tag $ACR_REPO:$NEW_TAG $ACR_REPO@${digest}

echo "✅ Image successfully tagged: $ACR_REPO:$NEW_TAG"
