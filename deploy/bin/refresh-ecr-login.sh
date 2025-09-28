#!/bin/bash

set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}
# No need to explicitly pick the namespace - this normally runs in its own namespace

DEFAULT_AWS_REGISTRY="767397850842.dkr.ecr.us-west-2.amazonaws.com"
AWS_REGION=${AWS_REGION:-us-west-2}

REGISTRY_PROVIDER=$(echo "${REGISTRY_PROVIDER:-aws}" | tr '[:upper:]' '[:lower:]')
REGISTRY_SERVER="${REGISTRY_SERVER:-}"
AZURE_REGISTRY_NAME="${AZURE_REGISTRY_NAME:-}"

docker_username="AWS"
docker_password=""

case "$REGISTRY_PROVIDER" in
  azure)
    if [[ -z "$AZURE_REGISTRY_NAME" ]]; then
      echo "AZURE_REGISTRY_NAME must be set when REGISTRY_PROVIDER is 'azure'." >&2
      exit 1
    fi

    if ! command -v az >/dev/null 2>&1; then
      echo "Azure CLI (az) is required to refresh Azure registry credentials." >&2
      exit 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
      echo "python3 is required to parse Azure registry credential responses." >&2
      exit 1
    fi

    echo "Fetching Azure Container Registry token for '$AZURE_REGISTRY_NAME'..."
    if ! login_output=$(az acr login --name "$AZURE_REGISTRY_NAME" --expose-token --output json); then
      echo "Failed to retrieve Azure Container Registry token." >&2
      exit 1
    fi

    docker_username=$(printf '%s' "$login_output" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("username", ""))')
    docker_password=$(printf '%s' "$login_output" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("accessToken", ""))')
    login_server=$(printf '%s' "$login_output" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("loginServer", ""))')

    if [[ -z "$docker_username" || -z "$docker_password" ]]; then
      echo "Azure login response did not include credentials." >&2
      exit 1
    fi

    if [[ -z "$REGISTRY_SERVER" || ! "$REGISTRY_SERVER" =~ \.azurecr\.io$ ]]; then
      if [[ -z "$login_server" ]]; then
        echo "Azure login response did not include a loginServer." >&2
        exit 1
      fi
      REGISTRY_SERVER="$login_server"
    fi

    echo "Fetched short-lived Azure Container Registry credentials."
    ;;
  aws|*)
    REGISTRY_SERVER=${REGISTRY_SERVER:-${ECR_REGISTRY:-$DEFAULT_AWS_REGISTRY}}
    echo "Fetching AWS ECR credentials for registry $REGISTRY_SERVER..."
    if ! docker_password=$(aws ecr get-login-password --region "$AWS_REGION"); then
      echo "Failed to get ECR password" >&2
      exit 1
    fi
    echo "Fetched short-lived ECR credentials from AWS"
    ;;
esac

if command -v docker >/dev/null 2>&1; then
    echo "$docker_password" | docker login \
        --username "$docker_username" \
        --password-stdin  \
        "$REGISTRY_SERVER"
else
    echo "Docker is not installed. Skipping docker registry login."
fi

$K delete --ignore-not-found secret registry-credentials

$K create secret docker-registry registry-credentials \
    --docker-server="$REGISTRY_SERVER" \
    --docker-username="$docker_username" \
    --docker-password="$docker_password"

echo "Stored registry credentials in secret registry-credentials"

