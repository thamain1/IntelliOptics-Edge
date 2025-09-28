#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/common.sh"

IMG="$ACR_LOGIN_SERVER/intellioptics-api:latest"

az acr login --name "$ACR" >/dev/null
( cd backend/api && docker build -t "$IMG" . && docker push "$IMG" )

API_PLAN=${API_PLAN:-io-api-plan}
WEBAPP=${WEBAPP:-io-api}

az appservice plan show -g "$AZR" -n "$API_PLAN" >/dev/null 2>&1 || \
  az appservice plan create -g "$AZR" -n "$API_PLAN" -l "$LOC" --is-linux --sku P1v3 >/dev/null

az webapp show -g "$AZR" -n "$WEBAPP" >/dev/null 2>&1 || \
  az webapp create -g "$AZR" -p "$API_PLAN" -n "$WEBAPP" -i "$IMG" >/dev/null

az webapp config appsettings set -g "$AZR" -n "$WEBAPP" --settings \
  AZ_SB_NAMESPACE=${AZ_SB_NAMESPACE:-} \
  AZ_SB_CONN_STR=${SERVICE_BUS_CONN:-} \
  AZ_BLOB_ACCOUNT=${AZ_BLOB_ACCOUNT:-} \
  AZ_BLOB_CONTAINER=${AZ_BLOB_CONTAINER:-images} \
  PG_HOST=${PG_HOST:-} PG_DB=${PG_DB:-intellioptics} PG_USER=${PG_USER:-} PG_PASSWORD=${PG_PASSWORD:-${PG_PASS:-}} PG_SSLMODE=${PG_SSLMODE:-require} \
  POSTGRES_DSN=${POSTGRES_DSN:-} \
  INTELLIOPTICS_API_TOKEN=${INTELLIOPTICS_API_TOKEN:-${INTELLOPTICS_API_TOKEN:-}} \
  INTELLIOPTICS_ENDPOINT=${INTELLIOPTICS_ENDPOINT:-${INTELLOPTICS_API_BASE:-}} \
  SB_QUEUE_LISTEN=${SB_QUEUE_LISTEN} SB_QUEUE_SEND=${SB_QUEUE_SEND} SB_QUEUE_FEEDBACK=${SB_QUEUE_FEEDBACK} \
  API_BASE_PATH=${API_BASE_PATH:-/v1} ALLOWED_ORIGINS=${ALLOWED_ORIGINS:-*} >/dev/null

HOST=$(az webapp show -g "$AZR" -n "$WEBAPP" --query defaultHostName -o tsv)
echo "API URL: https://$HOST"
