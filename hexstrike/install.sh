#!/usr/bin/env bash
#
# Put the `hexstrike` command on your PATH.
#
# Symlinks scripts/hexstrike into ~/.local/bin (or $HEXSTRIKE_BIN_DIR). A symlink
# rather than a copy, so `git pull` updates the command too.
#
#   ./hexstrike/install.sh
#   ./hexstrike/install.sh --uninstall
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${ROOT}/scripts/hexstrike"
BIN_DIR="${HEXSTRIKE_BIN_DIR:-${HOME}/.local/bin}"
DEST="${BIN_DIR}/hexstrike"

info() { printf '\033[36m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }

if [ "${1:-}" = "--uninstall" ]; then
  [ -L "$DEST" ] && { rm "$DEST"; ok "Removed ${DEST}"; } || warn "Nothing at ${DEST}"
  exit 0
fi

[ -f "$SRC" ] || { echo "[x] ${SRC} not found" >&2; exit 1; }
chmod +x "$SRC" "${ROOT}"/setup.sh "${ROOT}"/scripts/*.sh "${ROOT}"/scripts/*.py 2>/dev/null || true

mkdir -p "$BIN_DIR"
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "[x] ${DEST} exists and is not a symlink; move it and re-run." >&2
  exit 1
fi
ln -sfn "$SRC" "$DEST"
ok "Installed: ${DEST} -> ${SRC}"

# --- PATH check --------------------------------------------------------------
case ":${PATH}:" in
  *":${BIN_DIR}:"*)
    ok "${BIN_DIR} is already on your PATH"
    echo
    ok "Run it:  hexstrike"
    ;;
  *)
    warn "${BIN_DIR} is NOT on your PATH yet."
    echo
    case "${SHELL##*/}" in
      zsh)  rc="${HOME}/.zshrc"  ;;
      bash) rc="${HOME}/.bashrc" ;;
      fish) rc="${HOME}/.config/fish/config.fish" ;;
      *)    rc="your shell rc file" ;;
    esac
    if [ "${SHELL##*/}" = "fish" ]; then
      echo "    echo 'fish_add_path ${BIN_DIR}' >> ${rc}"
    else
      echo "    echo 'export PATH=\"${BIN_DIR}:\$PATH\"' >> ${rc}"
    fi
    echo "    exec \$SHELL"
    echo
    info "Or run it by full path today:  ${DEST}"
    ;;
esac
