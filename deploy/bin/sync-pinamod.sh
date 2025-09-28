#!/usr/bin/env bash
set -euo pipefail

required_env_vars=(
  "AZURE_CLIENT_ID"
  "AZURE_CLIENT_SECRET"
  "AZURE_TENANT_ID"
  "PINAMOD_DIR"
  "PINAMOD_STORAGE_ACCOUNT"
  "PINAMOD_STORAGE_CONTAINER"
)

for var in "${required_env_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "Environment variable $var is required but not set" >&2
    exit 1
  fi
done

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI (az) is not installed. Cannot sync pinamod artifacts." >&2
  exit 1
fi

PINAMOD_STORAGE_PREFIX=${PINAMOD_STORAGE_PREFIX:-pinamod}

if [ -z "$PINAMOD_STORAGE_PREFIX" ]; then
  blob_pattern="*"
else
  blob_pattern="${PINAMOD_STORAGE_PREFIX%/}/*"
fi

mkdir -p "$PINAMOD_DIR"

# Remove existing contents to mimic the --delete behaviour of aws s3 sync.
shopt -s dotglob nullglob
rm -rf "${PINAMOD_DIR}/"*
shopt -u dotglob

az login --service-principal \
  --username "$AZURE_CLIENT_ID" \
  --password "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID" \
  --output none

az storage blob download-batch \
  --account-name "$PINAMOD_STORAGE_ACCOUNT" \
  --source "$PINAMOD_STORAGE_CONTAINER" \
  --destination "$PINAMOD_DIR" \
  --pattern "$blob_pattern" \
  --auth-mode login \
  --overwrite true \
  --output none

echo "Synced pinamod artifacts from Azure storage container $PINAMOD_STORAGE_CONTAINER"
