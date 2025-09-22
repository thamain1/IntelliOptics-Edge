#!/bin/bash

# Put a specific tag on an existing image in ECR
# Assumptions:
# - The image is already built and pushed to ECR
# - The image is tagged with the git commit hash

set -e  # Exit immediately on error
set -o pipefail

ECR_ACCOUNT=${ECR_ACCOUNT:-767397850842}
ECR_REGION=${ECR_REGION:-us-west-2}

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

if [ -n "${ACR_LOGIN_SERVER}" ]; then
    REGISTRY_URL="${ACR_LOGIN_SERVER}"
else
    REGISTRY_URL="${ECR_ACCOUNT}.dkr.ecr.${ECR_REGION}.amazonaws.com"
fi

ECR_REPO="${REGISTRY_URL}/${EDGE_ENDPOINT_IMAGE}"

# Authenticate docker to the container registry
if [ -n "${ACR_LOGIN_SERVER}" ]; then
    if [ -n "${ACR_USERNAME}" ] && [ -n "${ACR_PASSWORD}" ]; then
        echo "Using provided ACR credentials for docker login"
        if ! printf '%s' "${ACR_PASSWORD}" | docker login \
                --username "${ACR_USERNAME}" \
                --password-stdin "${ACR_LOGIN_SERVER}"; then
            echo "Failed to authenticate to ${ACR_LOGIN_SERVER} with provided credentials" >&2
            exit 1
        fi
    else
        ACR_NAME=${ACR_NAME:-${ACR_LOGIN_SERVER%%.*}}
        echo "Logging into Azure Container Registry ${ACR_NAME} using az acr login"
        if ! az acr login --name "${ACR_NAME}"; then
            echo "Failed to authenticate to Azure Container Registry ${ACR_NAME} via az acr login" >&2
            exit 1
        fi
    fi
else
    aws ecr get-login-password --region ${ECR_REGION} | docker login \
                  --username AWS \
                  --password-stdin  ${REGISTRY_URL}
fi

# Tag the image with the new tag
# To do this, we need to pull the digest SHA of the existing multiplatform image
# and then create the tag on that SHA. Otherwise imagetools will create a tag for
# just the platform where the command is run.
echo "🏷️ Tagging image $ECR_REPO:$GIT_TAG with tag $NEW_TAG"
digest=$(docker buildx imagetools inspect $ECR_REPO:$GIT_TAG --format '{{json .}}' | jq -r .manifest.digest)
docker buildx imagetools create --tag $ECR_REPO:$NEW_TAG $ECR_REPO@${digest}

echo "✅ Image successfully tagged: $ECR_REPO:$NEW_TAG"

