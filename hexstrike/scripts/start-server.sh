#!/usr/bin/env bash
#
# Start the HexStrike AI API server from the repo-local virtualenv.
#
# Usage:
#   ./hexstrike/scripts/start-server.sh
#   ./hexstrike/scripts/start-server.sh --debug
#   ./hexstrike/scripts/start-server.sh --port 9999
#   ./hexstrike/scripts/start-server.sh --host 0.0.0.0     # expose deliberately
#   ./hexstrike/scripts/start-server.sh --upstream         # run upstream's
#                                                          # __main__ unchanged
#
# By default this goes through scripts/hexstrike_local.py, which binds
# 127.0.0.1. Upstream's own entrypoint hardcodes host="0.0.0.0" while printing
# 127.0.0.1, and the API has no authentication - see README.md.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PY="${HERE}/hexstrike-env/bin/python3"
LAUNCHER="${HERE}/scripts/hexstrike_local.py"
UPSTREAM_SERVER="${HERE}/vendor/hexstrike-ai/hexstrike_server.py"

[ -x "$VENV_PY" ] || { echo "[!] venv missing - run ${HERE}/setup.sh first" >&2; exit 1; }
[ -f "$UPSTREAM_SERVER" ] || { echo "[!] server missing - run ${HERE}/setup.sh first" >&2; exit 1; }

if [ -f "${HERE}/hexstrike.env" ]; then
  # shellcheck disable=SC1091
  set -a; source "${HERE}/hexstrike.env"; set +a
fi
export HEXSTRIKE_PORT="${HEXSTRIKE_PORT:-8888}"
export HEXSTRIKE_HOST="${HEXSTRIKE_HOST:-127.0.0.1}"

# --upstream bypasses our launcher entirely.
args=()
use_upstream=0
for arg in "$@"; do
  if [ "$arg" = "--upstream" ]; then use_upstream=1; else args+=("$arg"); fi
done

if [ "$use_upstream" -eq 1 ]; then
  echo "[!] Running upstream entrypoint - it will bind 0.0.0.0 regardless of HEXSTRIKE_HOST" >&2
  cd "$(dirname "$UPSTREAM_SERVER")"
  exec "$VENV_PY" "$UPSTREAM_SERVER" ${args[@]+"${args[@]}"}
fi

exec "$VENV_PY" "$LAUNCHER" ${args[@]+"${args[@]}"}
