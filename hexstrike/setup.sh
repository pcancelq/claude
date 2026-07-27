#!/usr/bin/env bash
#
# HexStrike AI - one-shot setup.
#
# Clones (or updates) the upstream hexstrike-ai repo into ./vendor/, creates a
# virtualenv and installs the Python dependencies. Safe to re-run.
#
# Usage:
#   ./hexstrike/setup.sh                 # full setup
#   ./hexstrike/setup.sh --skip-heavy    # skip angr/pwntools/mitmproxy (fast, ~1 min)
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="${HERE}/vendor"
SRC_DIR="${VENDOR_DIR}/hexstrike-ai"
VENV_DIR="${HERE}/hexstrike-env"
UPSTREAM="https://github.com/0x4m4/hexstrike-ai.git"
SKIP_HEAVY=0

for arg in "$@"; do
  case "$arg" in
    --skip-heavy) SKIP_HEAVY=1 ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

info() { printf '\033[36m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }

# --- 1. source -------------------------------------------------------------
mkdir -p "$VENDOR_DIR"
if [ -d "${SRC_DIR}/.git" ]; then
  info "Updating existing checkout in ${SRC_DIR}"
  git -C "$SRC_DIR" pull --ff-only
else
  info "Cloning ${UPSTREAM}"
  git clone "$UPSTREAM" "$SRC_DIR"
fi
ok "Source at ${SRC_DIR}"

# --- 2. virtualenv ---------------------------------------------------------
if [ ! -d "$VENV_DIR" ]; then
  info "Creating virtualenv at ${VENV_DIR}"
  python3 -m venv "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
python3 -m pip install --quiet --upgrade pip wheel
ok "Virtualenv ready ($(python3 --version))"

# --- 3. dependencies -------------------------------------------------------
if [ "$SKIP_HEAVY" -eq 1 ]; then
  # angr and pwntools are the slow ones and the server never imports them - they
  # only appear inside generated exploit-template strings. Everything below IS a
  # module-level import in hexstrike_server.py, mitmproxy included, so the server
  # will not start without them.
  warn "--skip-heavy: installing core deps only (no angr/pwntools)"
  python3 -m pip install \
    'flask>=2.3.0,<4.0.0' \
    'requests>=2.31.0,<3.0.0' \
    'psutil>=5.9.0,<6.0.0' \
    'fastmcp>=0.2.0,<1.0.0' \
    'beautifulsoup4>=4.12.0,<5.0.0' \
    'selenium>=4.15.0,<5.0.0' \
    'webdriver-manager>=4.0.0,<5.0.0' \
    'aiohttp>=3.8.0,<4.0.0' \
    'mitmproxy>=9.0.0,<11.0.0'
else
  info "Installing full requirements (angr/pwntools take a few minutes)"
  python3 -m pip install -r "${SRC_DIR}/requirements.txt"
fi
ok "Python dependencies installed"

# --- 4. client configs -----------------------------------------------------
info "Generating AI-client configs with absolute paths"
python3 "${HERE}/scripts/generate-client-config.py" --write

cat <<EOF

$(ok "Setup complete.")

  Start the server:   ${HERE}/scripts/start-server.sh
  Verify it:          ${HERE}/scripts/verify.sh
  Install CLI tools:  ${HERE}/scripts/install-security-tools.sh

  Ready-to-paste client configs are in: ${HERE}/configs/generated/
EOF
