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
say "Registering Codex as an MCP server inside Claude Code (user scope)"
claude mcp remove codex --scope user >/dev/null 2>&1 || true
claude mcp add --scope user --transport stdio codex -- codex mcp-server
ok "claude -> codex  (tools: mcp__codex__codex, mcp__codex__codex-reply)"

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
