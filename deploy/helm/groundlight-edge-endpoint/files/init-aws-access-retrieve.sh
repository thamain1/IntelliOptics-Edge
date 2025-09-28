#!/bin/bash

set -euo pipefail

REGISTRY_PROVIDER=$(echo "${REGISTRY_PROVIDER:-azure}" | tr '[:upper:]' '[:lower:]')

if [[ "$REGISTRY_PROVIDER" != "azure" ]]; then
  echo "Unsupported REGISTRY_PROVIDER '$REGISTRY_PROVIDER'. Supported providers: azure" >&2
  exit 1
fi

exec /bin/bash /app/init-azure-access-retrieve.sh "$@"
