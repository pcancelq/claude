# Claude Code + Codex, wired together

Two CLI agents on the same Linux box, able to call each other over MCP, sharing
one instruction file and one engagement scope.

## Why bother

Not because two agents are twice as fast — they aren't. Because in bug bounty
and pentest work the expensive mistake is the **false positive**: hours spent
writing up something that isn't real, or a duplicate report that burns program
reputation. Two models reaching the same conclusion *without seeing each other's
reasoning* is a genuinely stronger signal than one model asked twice.

The setup below buys you that, plus the ability to hand a subtask to whichever
agent is better at it.

## 1. Wire them

```bash
./dual-agent/setup.sh
```

That does three things:

**Claude Code → Codex.** Registers Codex as a stdio MCP server:

```bash
claude mcp add --scope user --transport stdio codex -- codex mcp-server
```

`codex mcp-server` starts Codex as a JSON-RPC server on stdio, exposing two
tools — `codex` (start a session) and `codex-reply` (continue one by
`threadId`). The `codex` tool takes `prompt`, `model`, `cwd`, `sandbox`
(`read-only` / `workspace-write` / `danger-full-access`), `approval-policy`
(`untrusted` / `on-request` / `never`), and arbitrary `config` overrides.

**Codex → Claude Code.** Registers Claude Code the other way:

```bash
codex mcp add claude_code -- claude mcp serve
```

`claude mcp serve` runs Claude Code as a stdio MCP server. It writes
`[mcp_servers.claude_code]` into `~/.codex/config.toml`; you can also hand-edit
that file:

```toml
[mcp_servers.claude_code]
command = "claude"
args = ["mcp", "serve"]
```

**Shared context.** Symlinks `CLAUDE.md` → `AGENTS.md`, so both agents read the
same rules. Codex reads `AGENTS.md` natively; Claude Code follows the symlink.
If you already have a real `CLAUDE.md`, add `@AGENTS.md` to it instead.

Verify:

```bash
claude mcp list
codex mcp list
claude -p 'Use the codex tool to print CODEX_OK and nothing else.'
```

## 2. Let network traffic out of the Codex sandbox

This is the step that trips people up on live testing. Codex's `workspace-write`
sandbox **blocks outbound network by default**, so recon tooling silently fails.

Per-run:

```bash
codex exec -c sandbox_workspace_write.network_access=true "..."
```

Persistent, in `~/.codex/config.toml`:

```toml
[sandbox_workspace_write]
network_access = true
```

On the Claude Code side the equivalent friction is permission prompts. Allowlist
your recon tools in `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(httpx:*)", "Bash(nuclei:*)", "Bash(subfinder:*)",
      "Bash(ffuf:*)", "Bash(curl:*)", "Bash(jq:*)"
    ],
    "deny": [
      "Bash(rm -rf:*)",
      "Read(./.env)", "Read(./**/*.pem)", "Read(./**/id_rsa*)"
    ]
  }
}
```

## 3. The cross-check workflow

```bash
./dual-agent/crosscheck.sh -s scope.json -e ./evidence \
  "Is the sort parameter in GetListProcessor.php actually injectable?"
```

Both agents get identical prompts and identical evidence, run in parallel,
neither sees the other. A third pass then adjudicates and is explicitly told not
to split the difference. Output lands in `crosscheck-<timestamp>/`:
`claude.md`, `codex.md`, `verdict.md`.

Flags: `-n` for offline/static analysis with no scope file, `-N` to allow Codex
network access, `-f` to read the task from a file.

## 4. Division of labor

Point each agent at what it's better at rather than running both on everything:

- **Claude Code** — orchestration, reading large evidence trees, correlating
  across many files, triage, writing the final report.
- **Codex** — exploit and PoC code, payload encoding, protocol-level fiddling,
  and acting as the independent verifier on anything Claude originated.

In practice: Claude does recon and spots the candidate; delegates PoC
construction to Codex through the `codex` tool; Codex's PoC comes back and
Claude validates it against the evidence; `crosscheck.sh` runs on anything
you're about to actually report.

## Caveats

**Recursion.** Both directions are live, so Claude can call Codex which can call
Claude. Nothing in MCP stops that. `AGENTS.md` sets a one-hop rule; keep it.

**Cost and latency.** Every cross-check is 3 agent invocations, one of them on
each vendor's billing. Use it on findings you're about to report, not on every
recon result.

**Correlated blind spots.** Both models were trained on overlapping public
security corpora. Agreement is evidence, not proof — they can be wrong the same
way, particularly on obscure or recently-disclosed classes. The adjudication
prompt asks whether convergence is meaningful or whether both made the same
assumption, precisely because of this.

**Verification honesty.** Never show one agent the other's reasoning before it
forms its own view. A verifier that has read the claim it's verifying tends to
agree with it, and you'll have paid for a rubber stamp.

**Authorization.** `crosscheck.sh` refuses to run without a scope file unless
you pass `-n`. That's deliberate — the scope file is the thing that makes
"analyze everything I give them" safe to say to an agent that can send traffic.

## Reference

- [Claude Code MCP docs](https://code.claude.com/docs/en/mcp) — `claude mcp add`, scopes, `claude mcp serve`
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference) — `-p`, `--permission-mode`, `--add-dir`
- [Codex configuration reference](https://developers.openai.com/codex/config-reference) — `[mcp_servers.*]`, sandbox settings
- [openai/codex](https://github.com/openai/codex) — `codex mcp-server` and `codex exec` source of truth
