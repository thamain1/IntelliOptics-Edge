#!/usr/bin/env bash
set -euo pipefail
[ -f .env ] || { echo "Missing .env at repo root"; exit 2; }
# shellcheck disable=SC1091
set -a; . ./.env; set +a
: "${AZ_RESOURCE_GROUP:?}"; : "${AZ_LOCATION:?}"; : "${ACR_LOGIN_SERVER:?}"; : "${INTELLIOPTICS_API_TOKEN:?}"
AZR=${AZ_RESOURCE_GROUP}; LOC=${AZ_LOCATION}
ACR=${ACR_LOGIN_SERVER%%.*}
SB_QUEUE_LISTEN=${SB_QUEUE_LISTEN:-image-queries}
SB_QUEUE_SEND=${SB_QUEUE_SEND:-inference-results}
SB_QUEUE_FEEDBACK=${SB_QUEUE_FEEDBACK:-feedback}
