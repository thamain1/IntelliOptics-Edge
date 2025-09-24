#!/bin/bash

# Put a specific tag on an existing image in the configured container
# registry. This script no longer depends on AWS ECR tooling.

set -euo pipefail

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

# Tag the image with the new tag
# To do this, we need to pull the digest SHA of the existing multiplatform image
# and then create the tag on that SHA. Otherwise imagetools will create a tag for
# just the platform where the command is run.
echo "🏷️ Tagging image $IMAGE_REPOSITORY:$GIT_TAG with tag $NEW_TAG"
digest=$(docker buildx imagetools inspect $IMAGE_REPOSITORY:$GIT_TAG --format '{{json .}}' | jq -r .manifest.digest)
docker buildx imagetools create --tag $IMAGE_REPOSITORY:$NEW_TAG $IMAGE_REPOSITORY@${digest}

echo "✅ Image successfully tagged: $IMAGE_REPOSITORY:$NEW_TAG"

