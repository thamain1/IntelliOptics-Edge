#!/usr/bin/env bash

# Determine the repository root relative to this script's location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_EDGE_CONFIG_PATH="${REPO_ROOT}/configs/edge-config.yaml"

if [[ ! -f "${DEFAULT_EDGE_CONFIG_PATH}" ]]; then
  echo "Default edge config not found at ${DEFAULT_EDGE_CONFIG_PATH}" >&2
  return 1 2>/dev/null || exit 1
fi

# Export the contents of the default edge configuration so the tests and Docker
# container startup mirror the production environment expectations.
EDGE_CONFIG_CONTENT="$(cat "${DEFAULT_EDGE_CONFIG_PATH}")"
export EDGE_CONFIG="${EDGE_CONFIG_CONTENT}"
