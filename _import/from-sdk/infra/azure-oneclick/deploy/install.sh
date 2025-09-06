#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
"$DIR/provision.sh"
"$DIR/appservice-api.sh"
"$DIR/aci-worker.sh"
