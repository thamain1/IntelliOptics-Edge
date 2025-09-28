#!/bin/bash

# Put a specific tag on an existing image in a container registry
# Assumptions:
# - The image is already built and pushed to the selected registry
# - The image is tagged with the git commit hash

set -e  # Exit immediately on error
set -o pipefail

# Ensure that you're in the same directory as this script before running it
cd "$(dirname "$0")"

source ./registry.sh

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
REGISTRY_URL=$(registry_url)
IMAGE_REF="${REGISTRY_URL}/${EDGE_ENDPOINT_IMAGE}"

# Authenticate docker/cli to registry
registry_login

# Tag the image with the new tag
# To do this, we need to pull the digest SHA of the existing multiplatform image
# and then create the tag on that SHA. Otherwise imagetools will create a tag for
# just the platform where the command is run.
echo "🏷️ Tagging image $IMAGE_REF:$GIT_TAG with tag $NEW_TAG"
registry_create_tag "$EDGE_ENDPOINT_IMAGE" "$GIT_TAG" "$NEW_TAG"

echo "✅ Image successfully tagged: $IMAGE_REF:$NEW_TAG"

