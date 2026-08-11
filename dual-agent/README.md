# Claude Code + Codex, wired together

Two CLI agents on the same Linux box, able to call each other over MCP, sharing
one instruction file and one engagement scope.

## Install on the testing box

Nothing here affects a machine until you run `setup.sh` on it.

```bash
git fetch origin claude/cloud-code-codex-integration-nlgtea
git checkout claude/cloud-code-codex-integration-nlgtea
./dual-agent/setup.sh

# recon tooling the allowlist and scope guard assume is on PATH
# (Kali: most are in the repos, the rest via go install)
which httpx subfinder nuclei ffuf katana dig jq
```

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
claude mcp add --scope user --transport stdio codex -- \
  codex -c approval_policy='"never"' \
        -c sandbox_mode='"workspace-write"' \
        -c sandbox_workspace_write.network_access=true \
        mcp-server
```

Root-level `-c` overrides are forwarded to `mcp-server`, so they configure this
registration without touching your interactive `codex` sessions. See
[section 3](#3-everyday-use--codex-in-all-your-work-not-just-hunt) for what the
three values buy and cost.

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

## 3. Everyday use — Codex in all your work, not just `/hunt`

`setup.sh` registers Codex at **user scope**, so `mcp__codex__codex` is live in
every project and every session. Nothing gates it behind a skill: a skill's
`allowed-tools` only pre-approves permission for that turn, it never restricts
what is otherwise available. Your existing skills keep working exactly as they
did, and any of them can reach Codex.

What was missing is that Claude has no reason to *think* of delegating. That's
what `delegation.md` fixes — `setup.sh` installs it into `~/.claude/CLAUDE.md`,
so the policy is in context for every project. It covers when handing work to
Codex is worth the round trip, when it isn't, and how to read the answer that
comes back. Re-running `setup.sh` replaces the block in place rather than
stacking copies, and leaves the rest of your memory file untouched.

The registration also gives Codex enough rope to be useful:

```
approval_policy = never            # no human in the MCP loop to approve
sandbox_mode    = workspace-write  # can run commands and write in the cwd
network_access  = true
```

These apply **only to the MCP registration** — your interactive `codex`
sessions still follow `~/.codex/config.toml`. If you'd rather Codex only ever
analyze, install with `CODEX_SANDBOX=read-only ./dual-agent/setup.sh`. Claude
can also narrow any individual call by passing `sandbox: "read-only"` to the
tool, which is the right setting for a second opinion.

Understand what `workspace-write` + `approval_policy = never` means before you
accept the default: Codex executes commands in the working directory without
asking you first. That is the price of it being useful unattended. It cannot
reach outside the working directory, and `danger-full-access` is deliberately
not offered by the installer.

## 4. The cross-check workflow

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

## 5. Skills and the scope gate

Skills and MCP are orthogonal — a skill is just instructions, and it can drive
MCP tools like any other. `.claude/skills/hunt/SKILL.md` gives you `/hunt`, which
pre-approves the recon tooling plus `mcp__codex__codex` for its turn and walks
the map → candidates → prove → verify → write-up loop.

```
/hunt api.example.net
```

One asymmetry: **skills are Claude Code only.** Codex doesn't read
`.claude/skills/`; its equivalent is `~/.codex/prompts/*.md` (now deprecated) or
its plugin system. That's fine here because Claude is the orchestrator — Codex
gets its rules from `AGENTS.md` and from the prompt Claude sends it.

The scope rules in `AGENTS.md` are only instructions, and an agent hunting for
an hour will drift. `.claude/hooks/scope-guard.py` is the actual enforcement: a
`PreToolUse` hook that extracts target hosts from every Bash/WebFetch call,
matches them against `scope.json` (wildcards, CIDRs, `out_of_scope` overriding
`in_scope`), and denies anything that doesn't match. It fails closed — a network
command whose target it can't parse gets blocked too.

It only ever *subtracts* permission. In-scope hosts return `defer`, so your
normal `settings.json` rules still apply rather than being silently bypassed.

Critically, it also gates `mcp__codex__*` calls. Codex runs in its own process
where this hook does not apply, so the delegation prompt is the last checkpoint
before work leaves Claude's control.

## 6. Division of labor

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

**These files live in the repo, not on your machine.** Clone or pull this branch
on the box you actually test from; `setup.sh` is what wires that machine.

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
