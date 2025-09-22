#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"  # script is in app/bin/
cd ../..

if [[ -z "${POETRY_ACTIVE:-}" ]] && command -v poetry >/dev/null 2>&1; then
    VENV_PATH="$(poetry env info --path 2>/dev/null || true)"
    if [[ -n "${VENV_PATH}" && -f "${VENV_PATH}/bin/activate" ]]; then
        # shellcheck disable=SC1090
        source "${VENV_PATH}/bin/activate"
    fi
elif [[ -d .venv ]]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
fi

python -m app.escalation_queue.manage_reader "$@"
