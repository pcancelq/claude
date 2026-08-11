---
name: hunt
description: Run a scoped bug bounty / pentest hunt against a target, delegating PoC construction to Codex and cross-verifying findings before reporting. Takes the target first; reads ./scope.json unless a scope file is given as the second argument.
argument-hint: "[target] [scope-file (default ./scope.json)]"
arguments: [target, scope]
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

Target / focus: `$target`
Scope file: `$scope` — if that is empty, use `./scope.json`.

## 0. Gate

Read the scope file first, before anything else.

Stop and ask if any of these is true:

- The scope file does not exist.
- It is still the unedited template (`engagement: "example-program"`, or
  `example.com` in `in_scope.domains`).
- `$target` is not covered by `in_scope`.

In each case say plainly what is wrong and what needs to go in the file. Do not
improvise a scope, do not guess that the target is probably fine, and do not
send a single request until it is fixed — `scope-guard.py` would block you
anyway, and burning turns on denied commands helps nobody.

Once it is valid, restate in one line what is in scope and what is excluded,
then proceed.

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
./dual-agent/crosscheck.sh -s <the scope file from step 0> -e ./evidence "<the specific claim>"
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
