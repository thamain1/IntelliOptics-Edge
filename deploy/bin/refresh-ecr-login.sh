#!/bin/bash
set -euo pipefail

K=${KUBECTL_CMD:-"kubectl"}
VALUES_FILE="$(dirname "$0")/../helm/groundlight-edge-endpoint/values.yaml"

usage() {
    cat <<USAGE
Usage: $0 [-f values.yaml]

Options:
  -f PATH   Override path to Helm values file (defaults to chart values)
USAGE
}

while getopts "f:h" opt; do
    case "$opt" in
        f)
            VALUES_FILE="$OPTARG"
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
done

if [ ! -f "$VALUES_FILE" ]; then
    echo "Values file '$VALUES_FILE' not found" >&2
    exit 1
fi

read_values() {
    python - <<'PYTHON' "$VALUES_FILE"
import shlex
import sys
import yaml

values_path = sys.argv[1]
with open(values_path, 'r', encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}
registry = data.get('registry', {}) or {}
aws = registry.get('aws', {}) or {}
azure = registry.get('azure', {}) or {}

def emit(key, value):
    if value is None:
        value = ''
    print(f"{key}={shlex.quote(str(value))}")

emit('REGISTRY_PROVIDER_VALUE', registry.get('provider', 'aws'))
emit('REGISTRY_SERVER_VALUE', registry.get('server', data.get('ecrRegistry', '')))
emit('REGISTRY_SECRET_NAME_VALUE', registry.get('secretName', 'registry-credentials'))
emit('REGISTRY_USERNAME_VALUE', registry.get('username', ''))
emit('REGISTRY_PASSWORD_CMD_VALUE', registry.get('passwordCmd', ''))
emit('AWS_REGION_VALUE', aws.get('region', data.get('awsRegion', 'us-west-2')))
emit('AZURE_REGISTRY_NAME_VALUE', azure.get('registryName', ''))
emit('AZURE_LOGIN_MODE_VALUE', azure.get('loginMode', 'servicePrincipal'))
emit('AZURE_CLIENT_ID_VALUE', azure.get('clientId', ''))
emit('AZURE_TENANT_ID_VALUE', azure.get('tenantId', ''))
emit('AZURE_CLIENT_SECRET_VALUE', azure.get('clientSecret', ''))
PYTHON
}

eval "$(read_values)"

REGISTRY_PROVIDER=${REGISTRY_PROVIDER:-$REGISTRY_PROVIDER_VALUE}
REGISTRY_SERVER=${REGISTRY_SERVER:-$REGISTRY_SERVER_VALUE}
REGISTRY_SECRET_NAME=${REGISTRY_SECRET_NAME:-$REGISTRY_SECRET_NAME_VALUE}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-$REGISTRY_USERNAME_VALUE}
REGISTRY_PASSWORD_CMD=${REGISTRY_PASSWORD_CMD:-$REGISTRY_PASSWORD_CMD_VALUE}
AWS_REGION=${AWS_REGION:-$AWS_REGION_VALUE}
AZURE_REGISTRY_NAME=${AZURE_REGISTRY_NAME:-$AZURE_REGISTRY_NAME_VALUE}
AZURE_LOGIN_MODE=${AZURE_LOGIN_MODE:-$AZURE_LOGIN_MODE_VALUE}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID:-$AZURE_CLIENT_ID_VALUE}
AZURE_TENANT_ID=${AZURE_TENANT_ID:-$AZURE_TENANT_ID_VALUE}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET:-$AZURE_CLIENT_SECRET_VALUE}

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_binary() {
    if ! command -v "$1" >/dev/null 2>&1; then
        die "Required binary '$1' is not installed"
    fi
}

create_docker_config() {
    local username="$1"
    local password="$2"
    local server="$3"
    local dest="$4"

    if [ -z "$server" ]; then
        die "Registry server is empty"
    fi

    local auth
    auth=$(printf '%s' "$username:$password" | base64 | tr -d '\n')
    cat <<EOF > "$dest"
{
  "auths": {
    "$server": {
      "username": "$username",
      "password": "$password",
      "auth": "$auth"
    }
  }
}
EOF
}

azure_login() {
    require_binary az
    case "$AZURE_LOGIN_MODE" in
        servicePrincipal)
            if [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_CLIENT_SECRET" ] || [ -z "$AZURE_TENANT_ID" ]; then
                die "AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, and AZURE_TENANT_ID must be set for service principal login"
            fi
            log "Logging into Azure using service principal"
            az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" >/tmp/az-login.log 2>&1 || {
                cat /tmp/az-login.log >&2
                die "az login failed"
            }
            ;;
        workloadIdentity)
            log "Logging into Azure using workload identity"
            az login --identity >/tmp/az-login.log 2>&1 || {
                cat /tmp/az-login.log >&2
                die "az login (identity) failed"
            }
            ;;
        none)
            log "Skipping Azure login as requested"
            ;;
        *)
            log "Logging into Azure using custom mode '$AZURE_LOGIN_MODE'"
            az login $AZURE_LOGIN_MODE >/tmp/az-login.log 2>&1 || {
                cat /tmp/az-login.log >&2
                die "az login failed"
            }
            ;;
    esac
}

derive_azure_registry_name() {
    if [ -n "$AZURE_REGISTRY_NAME" ]; then
        echo "$AZURE_REGISTRY_NAME"
        return
    fi
    local domain="$REGISTRY_SERVER"
    domain="${domain%%:*}"
    if [[ "$domain" =~ ^([^.]+)\.azurecr\.io$ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

REGISTRY_PASSWORD=""
case "$REGISTRY_PROVIDER" in
    aws)
        require_binary aws
        if [ -z "$REGISTRY_PASSWORD_CMD" ]; then
            REGISTRY_PASSWORD_CMD="aws ecr get-login-password --region ${AWS_REGION}"
        fi
        if [ -z "$REGISTRY_USERNAME" ]; then
            REGISTRY_USERNAME="AWS"
        fi
        ;;
    azure)
        azure_login
        if [ -z "$REGISTRY_USERNAME" ]; then
            REGISTRY_USERNAME="00000000-0000-0000-0000-000000000000"
        fi
        if [ -z "$REGISTRY_PASSWORD_CMD" ]; then
            local registry_name
            registry_name=$(derive_azure_registry_name)
            if [ -z "$registry_name" ]; then
                die "Unable to determine Azure registry name. Set AZURE_REGISTRY_NAME or REGISTRY_PASSWORD_CMD."
            fi
            REGISTRY_PASSWORD_CMD="az acr login --name ${registry_name} --expose-token --output tsv --query accessToken"
        fi
        ;;
    generic)
        if [ -z "$REGISTRY_USERNAME" ]; then
            die "REGISTRY_USERNAME must be set for generic provider"
        fi
        if [ -z "$REGISTRY_PASSWORD_CMD" ]; then
            die "REGISTRY_PASSWORD_CMD must be set for generic provider"
        fi
        ;;
    *)
        die "Unknown provider '$REGISTRY_PROVIDER'"
        ;;
 esac

if [ -z "$REGISTRY_PASSWORD_CMD" ]; then
    die "REGISTRY_PASSWORD_CMD is empty"
fi

log "Fetching registry password"
set +o pipefail
REGISTRY_PASSWORD=$(eval "$REGISTRY_PASSWORD_CMD")
status=$?
set -o pipefail
if [ $status -ne 0 ]; then
    die "Failed to fetch registry password"
fi

CONFIG_JSON=$(mktemp)
create_docker_config "$REGISTRY_USERNAME" "$REGISTRY_PASSWORD" "$REGISTRY_SERVER" "$CONFIG_JSON"

if command -v docker >/dev/null 2>&1; then
    log "Logging into Docker daemon for $REGISTRY_SERVER"
    printf '%s' "$REGISTRY_PASSWORD" | docker login --username "$REGISTRY_USERNAME" --password-stdin "$REGISTRY_SERVER"
else
    log "Docker not installed, skipping docker login"
fi

log "Updating Kubernetes secret '$REGISTRY_SECRET_NAME'"
$K delete --ignore-not-found secret "$REGISTRY_SECRET_NAME"
$K create secret generic "$REGISTRY_SECRET_NAME" \
    --type=kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson="$CONFIG_JSON"

rm -f "$CONFIG_JSON"
log "Stored registry credentials in secret $REGISTRY_SECRET_NAME"
