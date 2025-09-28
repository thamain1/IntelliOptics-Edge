#!/bin/bash

# Put a specific tag on an existing image in the container registry
# Assumptions:
# - The image is already built and pushed
# - The image is tagged with the git commit hash

set -euo pipefail

REGISTRY_PROVIDER=${REGISTRY_PROVIDER:-aws}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --registry-provider)
            REGISTRY_PROVIDER=$(echo "$2" | tr '[:upper:]' '[:lower:]')
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -ne 1 ]; then
    echo "Usage: $0 [--registry-provider aws|azure] <new-tag>" >&2
    exit 1
fi

NEW_TAG=$1

# Ensure that you're in the same directory as this script before running it
cd "$(dirname "$0")"

# Only the pipeline can create releases
if [[ "$NEW_TAG" == "pre-release" || "$NEW_TAG" == "release" || "$NEW_TAG" == "latest" ]]; then
    if [ -z "${GITHUB_ACTIONS:-}" ]; then
        echo "Error: The tag '$NEW_TAG' can only be used inside GitHub Actions."
        exit 1
    fi
fi

source ./registry.sh

GIT_TAG=$(./git-tag-name.sh)
EDGE_ENDPOINT_IMAGE=${EDGE_ENDPOINT_IMAGE:-edge-endpoint}  # v0.2.0 (fastapi inference server) compatible images
REGISTRY_URL=$(registry_get_url)
REPOSITORY_REF=$(registry_repository_ref "${EDGE_ENDPOINT_IMAGE}")

registry_login

echo "🏷️ Tagging image ${REPOSITORY_REF}:${GIT_TAG} with tag ${NEW_TAG}"
digest=$(registry_manifest_digest "${EDGE_ENDPOINT_IMAGE}" "${GIT_TAG}")
if [[ -z "$digest" || "$digest" == "None" ]]; then
    echo "Error: Unable to resolve digest for ${EDGE_ENDPOINT_IMAGE}:${GIT_TAG}" >&2
    exit 1
fi

docker buildx imagetools create --tag ${REPOSITORY_REF}:${NEW_TAG} ${REPOSITORY_REF}@${digest}

echo "✅ Image successfully tagged: ${REPOSITORY_REF}:${NEW_TAG}"
