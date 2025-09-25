#!/bin/bash

set -euo pipefail

if [ "${1:-}" == "validate" ]; then
  echo "Validating INTELLIOPTICS_API_TOKEN and INTELLIOPTICS_ENDPOINT..."
  if [ -z "${INTELLIOPTICS_API_TOKEN:-}" ]; then
    echo "INTELLIOPTICS_API_TOKEN is not set. Exiting."
    exit 1
  fi

  if [ -z "${INTELLIOPTICS_ENDPOINT:-}" ]; then
    echo "INTELLIOPTICS_ENDPOINT is not set. Exiting."
    exit 1
  fi
  echo "API token validation successful. Exiting."
  exit 0
fi

if [ -z "${AZURE_ACR_LOGIN_SERVER:-}" ]; then
  echo "AZURE_ACR_LOGIN_SERVER must be provided" >&2
  exit 1
fi

if [ -z "${AZURE_ACR_USERNAME:-}" ]; then
  echo "AZURE_ACR_USERNAME must be provided" >&2
  exit 1
fi

if [ -z "${AZURE_ACR_PASSWORD:-}" ]; then
  echo "AZURE_ACR_PASSWORD must be provided" >&2
  exit 1
fi

cat <<EOF_SHARED > /shared/credentials
[azure]
login_server = ${AZURE_ACR_LOGIN_SERVER}
username = ${AZURE_ACR_USERNAME}
password = ${AZURE_ACR_PASSWORD}
EOF_SHARED

echo "${AZURE_ACR_PASSWORD}" > /shared/token.txt

touch /shared/done
