#!/bin/bash

# Put a specific tag on an existing image in Azure Container Registry (ACR)
# Assumptions:
# - The image is already built and pushed to ACR
# - The image is tagged with the git commit hash

set -e  # Exit immediately on error
set -o pipefail

ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER:-intelliopticsedge.azurecr.io}
ACR_USERNAME=${ACR_USERNAME:-}
ACR_PASSWORD=${ACR_PASSWORD:-}
ACR_NAME=${ACR_NAME:-}

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
ACR_REPOSITORY=${ACR_REPOSITORY:-${EDGE_ENDPOINT_IMAGE}}

if [ -z "${ACR_LOGIN_SERVER}" ]; then
    echo "Error: ACR_LOGIN_SERVER must be set."
    exit 1
fi

ACR_IMAGE="${ACR_LOGIN_SERVER}/${ACR_REPOSITORY}"
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

# Tag the image with the new tag
# To do this, we need to pull the digest SHA of the existing multiplatform image
# and then create the tag on that SHA. Otherwise imagetools will create a tag for
# just the platform where the command is run.
echo "🏷️ Tagging image $ACR_IMAGE:$GIT_TAG with tag $NEW_TAG"
digest=$(docker buildx imagetools inspect $ACR_IMAGE:$GIT_TAG --format '{{json .}}' | jq -r .manifest.digest)
docker buildx imagetools create --tag $ACR_IMAGE:$NEW_TAG $ACR_IMAGE@${digest}

echo "✅ Image successfully tagged: $ACR_IMAGE:$NEW_TAG"

