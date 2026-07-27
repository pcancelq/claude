#!/usr/bin/env bash
#
# Health-check a running HexStrike server.
#
# Usage:
#   ./hexstrike/scripts/verify.sh                       # localhost:8888
#   ./hexstrike/scripts/verify.sh http://host:9999
#
set -euo pipefail

SERVER="${1:-http://localhost:${HEXSTRIKE_PORT:-8888}}"

echo "[*] GET ${SERVER}/health"
if ! curl -fsS --max-time 10 "${SERVER}/health"; then
  echo
  echo "[!] Server not responding at ${SERVER}. Is start-server.sh running?" >&2
  exit 1
fi
echo
echo

echo "[*] POST ${SERVER}/api/intelligence/analyze-target"
curl -fsS --max-time 30 -X POST "${SERVER}/api/intelligence/analyze-target" \
  -H "Content-Type: application/json" \
  -d '{"target": "example.com", "analysis_type": "comprehensive"}'
echo
echo
echo "[+] Server is up."
