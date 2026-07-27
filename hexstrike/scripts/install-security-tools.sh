#!/usr/bin/env bash
#
# Install the CLI security tools HexStrike wraps.
#
# HexStrike itself is only a bridge - each capability shells out to a real tool.
# Anything not installed here simply reports "tool unavailable" at runtime, so
# a partial install is fine.
#
# Usage:
#   ./hexstrike/scripts/install-security-tools.sh              # core set
#   ./hexstrike/scripts/install-security-tools.sh --all        # core + cloud + browser
#   ./hexstrike/scripts/install-security-tools.sh --check      # report what's present
#
# Targets Debian/Ubuntu/Kali (apt). On Kali 2024.1+ most of this is preinstalled.
#
set -uo pipefail

CORE_TOOLS=(
  # Network & reconnaissance
  nmap masscan amass nuclei dnsenum
  # Web application security
  gobuster feroxbuster dirsearch ffuf dirb nikto sqlmap wpscan wafw00f
  # Password & authentication
  hydra john hashcat medusa
  # Binary analysis & reverse engineering
  gdb radare2 binwalk checksec foremost steghide exiftool
)

# Go-based tools that apt often lacks; installed via `go install` when available.
GO_TOOLS=(
  "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
  "github.com/projectdiscovery/httpx/cmd/httpx@latest"
  "github.com/projectdiscovery/katana/cmd/katana@latest"
  "github.com/hahwul/dalfox/v2@latest"
)

PIPX_TOOLS=(theharvester arjun autorecon)
CLOUD_TOOLS=(prowler trivy)
MODE="core"

for arg in "$@"; do
  case "$arg" in
    --all)   MODE="all" ;;
    --check) MODE="check" ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

info() { printf '\033[36m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }

# --- check mode ------------------------------------------------------------
if [ "$MODE" = "check" ]; then
  missing=0
  for t in "${CORE_TOOLS[@]}" subfinder httpx katana dalfox theHarvester arjun; do
    if command -v "$t" >/dev/null 2>&1; then
      printf '\033[32m  ok  \033[0m %s\n' "$t"
    else
      printf '\033[31m miss \033[0m %s\n' "$t"
      missing=$((missing + 1))
    fi
  done
  echo
  echo "${missing} tool(s) missing. Run without --check to install."
  exit 0
fi

command -v apt-get >/dev/null 2>&1 || {
  warn "apt-get not found. This script targets Debian/Ubuntu/Kali."
  warn "On macOS: brew install ${CORE_TOOLS[*]}"
  exit 1
}

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

info "Updating package index"
$SUDO apt-get update -qq

# Install one at a time so a single unavailable package doesn't abort the run.
info "Installing core tools (${#CORE_TOOLS[@]} packages)"
failed=()
for tool in "${CORE_TOOLS[@]}"; do
  if $SUDO apt-get install -y -qq "$tool" >/dev/null 2>&1; then
    ok "$tool"
  else
    failed+=("$tool")
  fi
done
[ ${#failed[@]} -gt 0 ] && warn "Not in apt repos: ${failed[*]} (install from source or enable the Kali repos)"

# --- pipx tools ------------------------------------------------------------
if command -v pipx >/dev/null 2>&1 || $SUDO apt-get install -y -qq pipx >/dev/null 2>&1; then
  info "Installing pipx tools"
  for tool in "${PIPX_TOOLS[@]}"; do
    pipx install "$tool" >/dev/null 2>&1 && ok "$tool" || warn "pipx install $tool failed"
  done
else
  warn "pipx unavailable; skipping ${PIPX_TOOLS[*]}"
fi

# --- go tools --------------------------------------------------------------
if command -v go >/dev/null 2>&1; then
  info "Installing Go-based tools (into \$(go env GOPATH)/bin)"
  for tool in "${GO_TOOLS[@]}"; do
    go install "$tool" >/dev/null 2>&1 && ok "${tool%%@*}" || warn "go install $tool failed"
  done
  warn "Ensure \$(go env GOPATH)/bin is on your PATH"
else
  warn "Go toolchain not found; skipping subfinder/httpx/katana/dalfox"
fi

# --- optional extras -------------------------------------------------------
if [ "$MODE" = "all" ]; then
  info "Installing cloud/container security tools"
  for tool in "${CLOUD_TOOLS[@]}"; do
    $SUDO apt-get install -y -qq "$tool" >/dev/null 2>&1 && ok "$tool" || warn "$tool not in apt; see its docs"
  done

  info "Installing Chromium for the browser agent"
  $SUDO apt-get install -y -qq chromium chromium-driver >/dev/null 2>&1 \
    || $SUDO apt-get install -y -qq chromium-browser chromium-chromedriver >/dev/null 2>&1 \
    || warn "Chromium install failed; the browser agent will be unavailable"
fi

echo
ok "Done. Run with --check to see what resolved."
