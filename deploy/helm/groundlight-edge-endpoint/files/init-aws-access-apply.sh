#!/bin/bash

set -euo pipefail

SHARED_DIR=${SHARED_DIR:-/shared}
DONE_FILE="${DONE_FILE:-${SHARED_DIR}/done}"
REGISTRY_SERVER_FILE="${REGISTRY_SERVER_FILE:-${SHARED_DIR}/registry-server}"
REGISTRY_USERNAME_FILE="${REGISTRY_USERNAME_FILE:-${SHARED_DIR}/registry-username}"
REGISTRY_TOKEN_FILE="${REGISTRY_TOKEN_FILE:-${SHARED_DIR}/token.txt}"
TIMEOUT=${TIMEOUT:-60}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required to create registry credentials" >&2
  exit 1
fi

wait_seconds=0
while [ $wait_seconds -lt $TIMEOUT ]; do
  if [ -s "$REGISTRY_TOKEN_FILE" ]; then
    break
  fi

  if [ -f "$DONE_FILE" ] && [ -s "$REGISTRY_TOKEN_FILE" ]; then
    break
  fi

  sleep 1
  wait_seconds=$((wait_seconds + 1))
done

if [ ! -s "$REGISTRY_TOKEN_FILE" ]; then
  echo "Timed out waiting for registry credentials in $REGISTRY_TOKEN_FILE" >&2
  exit 1
fi

registry_server=""
if [ -f "$REGISTRY_SERVER_FILE" ]; then
  registry_server=$(cat "$REGISTRY_SERVER_FILE")
fi

registry_username=""
if [ -f "$REGISTRY_USERNAME_FILE" ]; then
  registry_username=$(cat "$REGISTRY_USERNAME_FILE")
fi

registry_password=$(cat "$REGISTRY_TOKEN_FILE")
if [ -z "$registry_password" ]; then
  echo "Registry password/token file $REGISTRY_TOKEN_FILE was empty" >&2
  exit 1
fi

if [ -z "$registry_username" ]; then
  registry_username="${REGISTRY_USERNAME:-AWS}"
fi

if [ -z "$registry_server" ]; then
  registry_server="${ECR_REGISTRY:-}"
fi

if [ -z "$registry_server" ]; then
  region="${ECR_REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}"
  if [ -n "$region" ] && [ -n "${AWS_ACCOUNT_ID:-}" ]; then
    registry_server="${AWS_ACCOUNT_ID}.dkr.ecr.${region}.amazonaws.com"
  elif [ -n "$region" ] && command -v aws >/dev/null 2>&1; then
    aws_account_id=$(aws sts get-caller-identity --query Account --output text)
    if [ -n "$aws_account_id" ]; then
      registry_server="${aws_account_id}.dkr.ecr.${region}.amazonaws.com"
    fi
  fi
fi

if [ -z "$registry_server" ]; then
  echo "Unable to determine registry server. Set REGISTRY_SERVER_FILE, ECR_REGISTRY, or provide AWS account/region." >&2
  exit 1
fi

# Trim any accidental whitespace/newlines from the parsed values
registry_server=$(printf '%s' "$registry_server" | tr -d '\r\n ')
registry_username=$(printf '%s' "$registry_username" | tr -d '\r\n ')
registry_password=$(printf '%s' "$registry_password" | tr -d '\r\n ')

if [ -z "$registry_username" ]; then
  echo "Registry username is empty after normalization" >&2
  exit 1
fi

if [ -z "$registry_password" ]; then
  echo "Registry password is empty after normalization" >&2
  exit 1
fi

echo "Creating/Updating docker-registry secret for server ${registry_server}..."

kubectl create secret docker-registry registry-credentials \
  --docker-server="$registry_server" \
  --docker-username="$registry_username" \
  --docker-password="$registry_password" \
  --dry-run=client -o yaml | kubectl apply -f -

