<!-- BEGIN codex-delegation -->
## Working with Codex

Codex is available in every session as the `codex` MCP tool (`codex-reply` to
continue a thread by `threadId`). It runs commands and writes files in the
working directory, and it has network access.

### When to hand work to Codex

- **Before acting on a diagnosis you are not certain of.** Describe the symptom
  and the evidence, not your conclusion, and see whether it lands in the same
  place.
- **To verify a claim you are about to make.** Anything you would put in a
  report, a PR description, or a finding.
- **Self-contained code with a clear contract** — a PoC, a parser, a repro
  script. Specify inputs, outputs and constraints; let it write the body.
- **Bulk mechanical analysis** over more material than is worth pulling into
  this context. Ask for the conclusion and the evidence, not the corpus.

### When not to

- Work you can just do. A delegation round trip costs time and money; use it
  when a second perspective or a saved context window is worth that.
- **If Codex invoked you, do the work yourself.** One hop per task — do not
  delegate back, and do not ask it to call you.
- Anything where you would have to paste your own reasoning in to explain the
  question. If it needs your conclusion to understand the task, it cannot
  independently check your conclusion.

### How to call it

Codex starts cold every time. It cannot see this conversation, your files, or
what you already tried. A prompt that assumes context gets you a confident
answer to the wrong question.

Include: the goal, the relevant file paths and contents, what you already ruled
out, and the exact shape of the answer you want back.

Set the parameters explicitly rather than relying on defaults:

- `cwd` — the directory it should work in.
- `sandbox` — `read-only` for analysis and verification, `workspace-write` when
  it genuinely needs to run or write something. Prefer `read-only`; it is the
  honest default for a second opinion.
- `model` — omit unless you have a reason.

### Reading the result

Codex is a second opinion, not an oracle. It is wrong at roughly the rate you
are, and confidently so.

- Agreement is evidence, not proof — you may both be wrong the same way, which
  is most likely on obscure or recent material.
- Disagreement means one of you is wrong; go find out which. Do not average the
  two answers or paper over the gap.
- If it asserts something checkable, check it before repeating it to me.
- Tell me when a conclusion came from Codex, and tell me when the two of you
  disagreed. Do not present a delegated answer as your own work.
<!-- END codex-delegation -->
