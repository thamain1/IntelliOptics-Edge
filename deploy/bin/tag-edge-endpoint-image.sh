#!/bin/bash

# Put a specific tag on an existing image in a container registry.
# Assumptions:
# - The image is already built and pushed to the registry
# - The image is tagged with the git commit hash

set -euo pipefail

# Ensure that you're in the same directory as this script before running it
cd "$(dirname "$0")"

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
        --password-stdin \
        "$REGISTRY_SERVER"
fi

echo "🏷️ Tagging image $IMAGE_REPOSITORY:$GIT_TAG with tag $NEW_TAG"
digest=$(docker buildx imagetools inspect $IMAGE_REPOSITORY:$GIT_TAG --format '{{json .}}' | jq -r .manifest.digest)
docker buildx imagetools create --tag $IMAGE_REPOSITORY:$NEW_TAG $IMAGE_REPOSITORY@${digest}

echo "✅ Image successfully tagged: $IMAGE_REPOSITORY:$NEW_TAG"
