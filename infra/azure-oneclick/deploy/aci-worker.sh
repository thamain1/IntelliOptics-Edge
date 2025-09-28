#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/common.sh"

IMAGE_NAME=${IMAGE_NAME:-intellioptics-worker}
IMAGE_TAG=${IMAGE_TAG:-latest}
REPO_ROOT=$(cd "$DIR/../../.." && pwd)

IMG="$ACR_LOGIN_SERVER/${IMAGE_NAME}:${IMAGE_TAG}"

az acr login --name "$ACR" >/dev/null
docker build \
  -t "$IMG" \
  -f "$REPO_ROOT/backend/worker/Dockerfile" \
  "$REPO_ROOT/backend/worker"
docker push "$IMG"

ACI_NAME=${ACI_NAME:-io-worker}
ENVVARS=(
  "SB_QUEUE_LISTEN=${SB_QUEUE_LISTEN}"
  "SB_QUEUE_SEND=${SB_QUEUE_SEND}"
  "INTELLIOPTICS_API_TOKEN=${INTELLIOPTICS_API_TOKEN:-${INTELLOPTICS_API_TOKEN}}"
  "INTELLIOPTICS_ENDPOINT=${INTELLIOPTICS_ENDPOINT:-${INTELLOPTICS_API_BASE:-}}"
  "DEFAULT_CONFIDENCE=${DEFAULT_CONFIDENCE:-0.9}"
  "DEFAULT_TIMEOUT=${DEFAULT_TIMEOUT:-30}"
)
[ -n "${SERVICE_BUS_CONN:-}" ] && ENVVARS+=("SERVICE_BUS_CONN=$SERVICE_BUS_CONN")
[ -n "${AZ_SB_NAMESPACE:-}" ] && ENVVARS+=("AZ_SB_NAMESPACE=$AZ_SB_NAMESPACE")
[ -n "${POSTGRES_DSN:-}" ] && ENVVARS+=("POSTGRES_DSN=$POSTGRES_DSN")
[ -n "${PG_HOST:-}" ] && ENVVARS+=("PG_HOST=$PG_HOST" "PG_DB=${PG_DB:-intellioptics}" "PG_USER=$PG_USER" "PG_PASSWORD=$PG_PASSWORD" "PG_SSLMODE=${PG_SSLMODE:-require}")

az container create \
  -g "$AZR" -n "$ACI_NAME" -l "$LOC" \
  --image "$IMG" \
  --restart-policy Always \
  --cpu ${ACI_CPU:-1} --memory ${ACI_MEM_GB:-2} \
  --assign-identity \
  $(printf -- "--environment-variables %s " "${ENVVARS[@]}")

az container logs -g "$AZR" -n "$ACI_NAME" --follow || true
