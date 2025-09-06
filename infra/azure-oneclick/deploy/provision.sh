#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/common.sh"

az group create -n "$AZR" -l "$LOC" >/dev/null

# ACR (create if missing)
az acr show -n "$ACR" >/dev/null 2>&1 || az acr create -n "$ACR" -g "$AZR" -l "$LOC" --sku Basic >/dev/null

# Service Bus
if [ -n "${SERVICE_BUS_CONN:-}" ]; then
  echo "[info] Using existing Service Bus connection string"
else
  : "${AZ_SB_NAMESPACE:?Set AZ_SB_NAMESPACE or SERVICE_BUS_CONN}"
  az servicebus namespace show -g "$AZR" -n "$AZ_SB_NAMESPACE" >/dev/null 2>&1 || \
    az servicebus namespace create -g "$AZR" -n "$AZ_SB_NAMESPACE" -l "$LOC" --sku Standard >/dev/null
  for q in "$SB_QUEUE_LISTEN" "$SB_QUEUE_SEND" "$SB_QUEUE_FEEDBACK"; do
    az servicebus queue create -g "$AZR" --namespace-name "$AZ_SB_NAMESPACE" -n "$q" >/dev/null || true
  done
fi

# Storage
if [ -n "${AZ_BLOB_ACCOUNT:-}" ]; then
  az storage account show -g "$AZR" -n "$AZ_BLOB_ACCOUNT" >/dev/null 2>&1 || \
    az storage account create -g "$AZR" -n "$AZ_BLOB_ACCOUNT" -l "$LOC" --sku Standard_LRS >/dev/null
  az storage container create --account-name "$AZ_BLOB_ACCOUNT" -n "${AZ_BLOB_CONTAINER:-images}" >/dev/null || true
fi

# Postgres: assume provided externally
