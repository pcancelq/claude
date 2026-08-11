#!/usr/bin/env bash
# Wire Claude Code and Codex CLI together over MCP, in both directions.
#
#   Claude Code --(stdio MCP)--> codex mcp-server   exposes tools: codex, codex-reply
#   Codex CLI   --(stdio MCP)--> claude mcp serve   exposes Claude Code's own tools
#
# Idempotent: re-running replaces the existing registrations.

set -euo pipefail

BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'

say()  { printf '%s==>%s %s\n' "$BOLD" "$OFF" "$*"; }
ok()   { printf '  %s+%s %s\n' "$GREEN" "$OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$OFF" "$*"; }
die()  { printf '  %sx%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

command -v claude >/dev/null || die "claude not on PATH (install: npm i -g @anthropic-ai/claude-code)"
command -v codex  >/dev/null || die "codex not on PATH (install: npm i -g @openai/codex)"

say "Found both CLIs"
ok "claude $(claude --version 2>/dev/null | head -1)"
ok "codex  $(codex --version 2>/dev/null | head -1)"

# ---------------------------------------------------------------------------
# Direction 1: Claude Code can call Codex
# ---------------------------------------------------------------------------
# Root-level `-c` overrides are forwarded to the mcp-server subcommand, and they
# apply only to this registration - your interactive `codex` sessions keep
# whatever is in ~/.codex/config.toml.
#
# Why these values: there is no human in the MCP loop to answer an approval
# prompt, so an approval policy other than "never" makes Codex hang mid-call.
# CODEX_SANDBOX picks how much rope that buys it:
#
#   read-only        analysis only; cannot run commands or write files
#   workspace-write  can run commands and write inside the working directory  [default]
#
# danger-full-access is deliberately not offered. If you want it, pass it per
# call via the tool's own `sandbox` parameter, where it is a visible decision.
CODEX_SANDBOX="${CODEX_SANDBOX:-workspace-write}"
case "$CODEX_SANDBOX" in
  read-only|workspace-write) ;;
  *) die "CODEX_SANDBOX must be read-only or workspace-write (got '$CODEX_SANDBOX')" ;;
esac

say "Registering Codex as an MCP server inside Claude Code (user scope)"
claude mcp remove codex --scope user >/dev/null 2>&1 || true
claude mcp add --scope user --transport stdio codex -- \
  codex -c approval_policy='"never"' \
        -c sandbox_mode="\"$CODEX_SANDBOX\"" \
        -c sandbox_workspace_write.network_access=true \
        mcp-server
ok "claude -> codex  (tools: mcp__codex__codex, mcp__codex__codex-reply)"
ok "sandbox: $CODEX_SANDBOX, approvals: never, network: on"
if [[ "$CODEX_SANDBOX" == "workspace-write" ]]; then
  warn "Codex will run commands in the working directory without asking."
  warn "Re-run with CODEX_SANDBOX=read-only if you'd rather it only analyze."
fi

# ---------------------------------------------------------------------------
# Direction 2: Codex can call Claude Code
# ---------------------------------------------------------------------------
say "Registering Claude Code as an MCP server inside Codex"
codex mcp remove claude_code >/dev/null 2>&1 || true
codex mcp add claude_code -- claude mcp serve
ok "codex -> claude  (writes [mcp_servers.claude_code] to ~/.codex/config.toml)"

# ---------------------------------------------------------------------------
# Shared instruction file: one brain, two front-ends
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
say "Linking shared context file"
if [[ -f "$REPO_ROOT/CLAUDE.md" && ! -L "$REPO_ROOT/CLAUDE.md" ]]; then
  warn "CLAUDE.md exists and is a real file - leaving it alone."
  warn "To share context, add this line to it:  @AGENTS.md"
else
  ln -sfn AGENTS.md "$REPO_ROOT/CLAUDE.md"
  ok "CLAUDE.md -> AGENTS.md (Codex reads AGENTS.md, Claude follows the symlink)"
fi

# ---------------------------------------------------------------------------
# Always-on delegation policy: makes Claude actually reach for Codex in every
# project, not just inside a skill that names it.
# ---------------------------------------------------------------------------
say "Installing delegation policy into ~/.claude/CLAUDE.md"
USER_MEM="$HOME/.claude/CLAUDE.md"
mkdir -p "$HOME/.claude"
touch "$USER_MEM"
if grep -q "BEGIN codex-delegation" "$USER_MEM"; then
  # Replace the existing block rather than appending a second copy.
  python3 - "$USER_MEM" "$(dirname "${BASH_SOURCE[0]}")/delegation.md" <<'PY'
import re, sys
mem, block = sys.argv[1], sys.argv[2]
text = open(mem).read()
new = open(block).read()
text = re.sub(r"<!-- BEGIN codex-delegation -->.*?<!-- END codex-delegation -->\n?",
              new, text, flags=re.S)
open(mem, "w").write(text)
PY
  ok "updated existing block in $USER_MEM"
else
  printf '\n' >> "$USER_MEM"
  cat "$(dirname "${BASH_SOURCE[0]}")/delegation.md" >> "$USER_MEM"
  ok "appended to $USER_MEM (applies to every project)"
fi

say "Verifying"
claude mcp list 2>/dev/null | sed 's/^/  /' || warn "claude mcp list failed"
codex  mcp list 2>/dev/null | sed 's/^/  /' || warn "codex mcp list failed"

cat <<'EOF'

Done. Quick smoke test:

  claude -p 'Use the codex tool to print the string CODEX_OK and nothing else.'
  codex exec 'Use the claude_code MCP server to print CLAUDE_OK and nothing else.'

Note: both directions are live, so an agent can call the other agent which can
call back. Keep the loop one-way per task - see AGENTS.md.
EOF
