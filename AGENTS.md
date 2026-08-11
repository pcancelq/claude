# Shared agent context

Read by **Codex** (as `AGENTS.md`) and by **Claude Code** (via the `CLAUDE.md`
symlink). One file, both agents, same rules.

## What this repo is

Security research workspace: penetration testing and bug bounty work.
Deliverables are reproducible PoCs and written findings, not scan dumps.

## Engagement scope — read before touching a target

Every run works against a scope file (see `dual-agent/scope.example.json`).

- Never send traffic to a host that is not in `in_scope`. If the scope file is
  missing, stop and ask.
- Respect `rules.max_requests_per_second`. Prefer targeted requests over
  broad automated sweeps.
- Stop at proof of access. Demonstrate the vulnerability, do not harvest data,
  pivot further, or persist anything on the target.
- Destructive HTTP verbs and anything that could degrade availability need an
  explicit human go-ahead in the transcript first.

## Division of labor

The two agents are not interchangeable — give each the work it is better at.

| Work | Owner |
|---|---|
| Recon orchestration, reading large evidence trees, correlating across files | Claude Code |
| Triage: is this a real finding or noise | Claude Code, verified by Codex |
| Exploit / PoC code, payload encoding, protocol fiddling | Codex |
| Independent second opinion on a suspected finding | whichever agent did *not* originate it |
| Final report writing | Claude Code |

## Cross-agent calling

Both directions are wired over MCP:

- Claude Code reaches Codex through the `codex` MCP tool.
- Codex reaches Claude Code through the `claude_code` MCP server.

Rules to keep this from turning into a loop:

1. **One hop per task.** If you were invoked *by* the other agent, do the work
   yourself. Do not delegate back.
2. When delegating, hand over full context — the other agent starts cold and
   cannot see your conversation.
3. When you are asked to verify another agent's finding, do not read its
   reasoning first. Reproduce independently, then compare. A verification that
   just agrees with the prompt is worthless.

## Findings bar

A finding is only real when all four hold:

1. Reproducible from a clean session (cookies/tokens stated explicitly).
2. Has concrete impact, described as what an attacker gains.
3. Is in scope, both host and finding class.
4. Is not already known — check the program's published duplicates/exclusions.

Anything failing these goes in `notes/`, not in a report.

## PoC conventions

Match `modx_sqli_poc.py`: a module docstring naming the vulnerable code path
and the technique, argparse CLI, no hardcoded targets, no third-party deps
beyond `requests` unless necessary.
