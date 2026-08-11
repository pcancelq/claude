---
name: hunt
description: Run a scoped bug bounty / pentest hunt against a target, delegating PoC construction to Codex and cross-verifying findings before reporting. Use when the user gives a scope file and a target to test.
argument-hint: "[scope-file] [target-or-focus]"
arguments: [scope, target]
allowed-tools:
  - Read
  - Grep
  - Glob
  - Write
  - TodoWrite
  - mcp__codex__codex
  - mcp__codex__codex-reply
  - Bash(httpx:*)
  - Bash(subfinder:*)
  - Bash(nuclei:*)
  - Bash(ffuf:*)
  - Bash(katana:*)
  - Bash(curl:*)
  - Bash(dig:*)
  - Bash(jq:*)
---

# Scoped hunt

Scope file: `$scope` (default `./scope.json` if empty)
Target / focus: `$target`

## 0. Gate

Read the scope file first. If it is missing, stop and ask — do not improvise a
scope. Restate in one line what is in scope and what is excluded, then proceed.

`.claude/hooks/scope-guard.py` independently blocks out-of-scope traffic. Treat
a `scope-guard: BLOCKED` message as final: do not rephrase the command, do not
try a different tool, do not retry. Report it and move on.

Honor `rules.max_requests_per_second`. Add `rules.required_header` to every
request that supports it.

## 1. Map

Enumerate only what the scope allows. Prefer passive sources first, then light
active probing. Write raw output to `evidence/<host>/` — never summarize away
the raw artifact, later steps need it.

Stop and show me the attack surface before moving to phase 2. Do not start
probing for vulnerabilities on your own.

## 2. Candidates

From the surface, list candidate issues ranked by expected impact. For each:
the specific endpoint/parameter, the class, and why this target plausibly has
it. Skip anything in `out_of_scope.findings`.

Ask me which to pursue. A list of forty low-signal candidates is worse than
three good ones.

## 3. Prove

For each approved candidate:

1. Establish the vulnerable behavior with the smallest possible request.
2. Delegate PoC construction to Codex via the `codex` tool. Send full context —
   Codex starts cold and sees none of this conversation. Ask for a standalone
   script matching the conventions in `AGENTS.md`.
3. Run the PoC yourself against the target and confirm it reproduces from a
   clean session.

Stop at proof. Demonstrate access; do not enumerate records, pivot, or write
anything to the target.

## 4. Verify before reporting

Anything you intend to report goes through independent verification:

```
./dual-agent/crosscheck.sh -s $scope -e ./evidence "<the specific claim>"
```

Do not paste your own reasoning into that prompt. The value is that the second
opinion is uncontaminated — a verifier that has read your argument will agree
with it.

Apply the findings bar from `AGENTS.md`: reproducible, real impact, in scope,
not a known duplicate. Anything failing it goes to `notes/`, not a report.

## 5. Write up

One markdown file per confirmed finding in `findings/`: summary, affected
endpoint, reproduction steps, PoC invocation, impact, suggested remediation.
Impact is what an attacker gains, in plain terms. No CVSS theater.

## Discipline

- Never widen scope on your own initiative, even if something adjacent looks
  interesting. Surface it and ask.
- Never claim a finding you have not reproduced.
- If a phase produces nothing, say so plainly. A clean result is a real result;
  inventing marginal findings to look productive wastes both our time.
