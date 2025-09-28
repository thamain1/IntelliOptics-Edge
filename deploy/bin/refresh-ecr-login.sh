#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHART_DIR=${CHART_DIR:-$SCRIPT_DIR/../helm/groundlight-edge-endpoint}
VALUES_FILE=${VALUES_FILE:-$CHART_DIR/values.yaml}
K=${KUBECTL_CMD:-kubectl}

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--values path]

Environment overrides:
  REGISTRY_PROVIDER, REGISTRY_SERVER, REGISTRY_USERNAME,
  REGISTRY_PASSWORD_CMD, REGISTRY_PASSWORD, REGISTRY_SECRET_NAME,
  REGISTRY_AWS_REGION, AZURE_REGISTRY_NAME.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --values)
      VALUES_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to parse Helm values." >&2
  exit 1
fi

parse_values() {
python3 - "$VALUES_FILE" <<'PY'
import sys
from pathlib import Path

def parse_simple_yaml(path: Path):
    root = {}
    stack = [root]
    indents = [-1]
    for raw_line in path.read_text().splitlines():
        line = raw_line.split('#', 1)[0].rstrip('\n')
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(' '))
        while len(stack) > 1 and indent <= indents[-1]:
            stack.pop()
            indents.pop()
        if ':' not in line:
            continue
        key, value = line.strip().split(':', 1)
        value = value.strip()
        current = stack[-1]
        if not value:
            new_dict = {}
            current[key] = new_dict
            stack.append(new_dict)
            indents.append(indent)
        else:
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            current[key] = value
    return root

data = parse_simple_yaml(Path(sys.argv[1]))
registry = data.get('registry', {})
registry_aws = registry.get('aws', {})
registry_azure = registry.get('azure', {})
print(f"provider={registry.get('provider', '')}")
print(f"server={registry.get('server', '') or data.get('ecrRegistry', '')}")
print(f"username={registry.get('username', '')}")
print(f"passwordCommand={registry.get('passwordCommand', '')}")
print(f"secretName={registry.get('secretName', 'registry-credentials')}")
print(f"awsRegion={registry_aws.get('region', '') or data.get('awsRegion', '')}")
print(f"azureRegistryName={registry_azure.get('registryName', '')}")
PY
}

declare -A VALUES=()
while IFS='=' read -r key value; do
  VALUES[$key]=$value
done < <(parse_values)

PROVIDER=${REGISTRY_PROVIDER:-${VALUES[provider]:-aws}}
SERVER=${REGISTRY_SERVER:-${VALUES[server]:-}}
USERNAME=${REGISTRY_USERNAME:-${VALUES[username]:-}}
PASSWORD_CMD=${REGISTRY_PASSWORD_CMD:-${VALUES[passwordCommand]:-}}
PASSWORD=${REGISTRY_PASSWORD:-}
SECRET_NAME=${REGISTRY_SECRET_NAME:-${VALUES[secretName]:-registry-credentials}}
AWS_REGION=${REGISTRY_AWS_REGION:-${VALUES[awsRegion]:-}}
AZURE_REGISTRY_NAME=${AZURE_REGISTRY_NAME:-${VALUES[azureRegistryName]:-}}

if [ -z "$PROVIDER" ]; then
  PROVIDER=aws
fi

log() {
  echo "[refresh-registry-login] $*"
}

fetch_password() {
  case "$PROVIDER" in
    aws|AWS)
      if [ -z "$PASSWORD" ]; then
        if [ -z "$PASSWORD_CMD" ]; then
          if ! command -v aws >/dev/null 2>&1; then
            log "AWS CLI is required for provider '$PROVIDER'." >&2
            return 1
          fi
          if [ -z "$AWS_REGION" ]; then
            AWS_REGION=${AWS_REGION:-us-west-2}
          fi
          PASSWORD=$(aws ecr get-login-password --region "$AWS_REGION")
        else
          # shellcheck disable=SC2086
          PASSWORD=$(eval $PASSWORD_CMD)
        fi
      fi
      if [ -z "$USERNAME" ]; then
        USERNAME=AWS
      fi
      ;;
    azure|AZURE)
      if [ -z "$PASSWORD" ]; then
        if [ -n "$PASSWORD_CMD" ]; then
          # shellcheck disable=SC2086
          PASSWORD=$(eval $PASSWORD_CMD)
        else
          if ! command -v az >/dev/null 2>&1; then
            log "Azure CLI is required for provider '$PROVIDER'." >&2
            return 1
          fi
          local acr_name
          acr_name="$AZURE_REGISTRY_NAME"
          if [ -z "$acr_name" ] && [ -n "$SERVER" ]; then
            if [[ "$SERVER" =~ ^([^.]+)\.azurecr\.io$ ]]; then
              acr_name="${BASH_REMATCH[1]}"
            fi
          fi
          if [ -z "$acr_name" ]; then
            log "Azure registry name is not configured. Set AZURE_REGISTRY_NAME or registry.azure.registryName." >&2
            return 1
          fi
          local login_json
          login_json=$(mktemp)
          az acr login --name "$acr_name" --expose-token --output json >"$login_json"
          PASSWORD=$(sed -n 's/.*"accessToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$login_json" | head -n1)
          if [ -z "$PASSWORD" ]; then
            rm -f "$login_json"
            log "Failed to retrieve Azure ACR access token." >&2
            return 1
          fi
          if [ -z "$SERVER" ]; then
            SERVER=$(sed -n 's/.*"loginServer"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$login_json" | head -n1)
          fi
          if [ -z "$USERNAME" ]; then
            USERNAME=$(sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$login_json" | head -n1)
          fi
          rm -f "$login_json"
        fi
      fi
      if [ -z "$USERNAME" ]; then
        USERNAME=00000000-0000-0000-0000-000000000000
      fi
      ;;
    *)
      if [ -z "$PASSWORD" ]; then
        if [ -z "$PASSWORD_CMD" ]; then
          log "Password command or REGISTRY_PASSWORD must be provided for provider '$PROVIDER'." >&2
          return 1
        fi
        # shellcheck disable=SC2086
        PASSWORD=$(eval $PASSWORD_CMD)
      fi
      if [ -z "$USERNAME" ]; then
        log "REGISTRY_USERNAME must be provided for provider '$PROVIDER'." >&2
        return 1
      fi
      ;;
  esac

  if [ -z "$SERVER" ]; then
    log "Registry server is not configured." >&2
    return 1
  fi
}

fetch_password

if command -v docker >/dev/null 2>&1; then
  printf '%s' "$PASSWORD" | docker login --username "$USERNAME" --password-stdin "$SERVER"
else
  log "Docker is not installed; skipping local registry login."
fi

$K delete --ignore-not-found secret "$SECRET_NAME"
$K create secret docker-registry "$SECRET_NAME" \
  --docker-server="$SERVER" \
  --docker-username="$USERNAME" \
  --docker-password="$PASSWORD"

log "Stored credentials for $SERVER in secret $SECRET_NAME"
