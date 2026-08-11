#!/usr/bin/env bash
# Run Claude Code and Codex over the same evidence independently, then have a
# third pass adjudicate the two answers.
#
# The point is false-positive control. Two models that reached the same
# conclusion without seeing each other's reasoning is a much stronger signal
# than one model asked twice.
#
# Usage:
#   ./crosscheck.sh "Is the sort parameter in GetListProcessor.php injectable?"
#   ./crosscheck.sh -f task.md -e ./evidence -s ./scope.json
#
# Options:
#   -f FILE     read the task from FILE instead of the argument
#   -e DIR      evidence directory both agents may read (default: cwd)
#   -s FILE     scope file (default: ./scope.json, required unless -n)
#   -n          no scope file - static/offline analysis only, no target traffic
#   -o DIR      output directory (default: ./crosscheck-<timestamp>)
#   -N          allow Codex network access (off by default)

set -euo pipefail

TASK=""; TASK_FILE=""; EVIDENCE="$PWD"; SCOPE="./scope.json"
NO_SCOPE=0; NET=0; OUT=""

while getopts "f:e:s:o:nN" opt; do
  case "$opt" in
    f) TASK_FILE="$OPTARG" ;;
    e) EVIDENCE="$OPTARG" ;;
    s) SCOPE="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    n) NO_SCOPE=1 ;;
    N) NET=1 ;;
    *) sed -n '2,22p' "$0" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

[[ -n "$TASK_FILE" ]] && TASK="$(cat "$TASK_FILE")" || TASK="${1:-}"
[[ -n "$TASK" ]] || { echo "error: no task given" >&2; exit 2; }

SCOPE_BLOCK="Static analysis only. Do NOT send any network traffic to any host."
if (( ! NO_SCOPE )); then
  [[ -f "$SCOPE" ]] || {
    echo "error: scope file '$SCOPE' not found. Pass -s FILE, or -n for offline analysis." >&2
    exit 2
  }
  SCOPE_BLOCK="Engagement scope (authoritative - refuse anything outside it):
$(cat "$SCOPE")"
fi

OUT="${OUT:-./crosscheck-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

PROMPT="$SCOPE_BLOCK

Evidence directory: $EVIDENCE

Task:
$TASK

Answer with exactly these sections:
## VERDICT
One of: CONFIRMED / LIKELY / UNPROVEN / NOT-A-FINDING
## REASONING
The specific evidence that drove the verdict. Cite file:line or request/response pairs.
## REPRODUCTION
Exact steps or a minimal PoC. Write 'none' if the verdict is NOT-A-FINDING.
## IMPACT
What an attacker actually gains. No CVSS hand-waving.
## UNCERTAINTY
What you could not check and what would settle it."

printf '%s\n' "$PROMPT" > "$OUT/prompt.md"

echo "==> Running both agents independently (output: $OUT)"

claude -p "$PROMPT" \
  --add-dir "$EVIDENCE" \
  --permission-mode plan \
  > "$OUT/claude.md" 2> "$OUT/claude.err" &
CLAUDE_PID=$!

CODEX_CFG=(-c sandbox_mode="workspace-write")
(( NET )) && CODEX_CFG+=(-c sandbox_workspace_write.network_access=true)

codex exec "${CODEX_CFG[@]}" --skip-git-repo-check \
  --output-last-message "$OUT/codex.md" \
  "$PROMPT" > "$OUT/codex.log" 2> "$OUT/codex.err" &
CODEX_PID=$!

FAILED=0
wait $CLAUDE_PID || { echo "  ! claude exited nonzero (see $OUT/claude.err)"; FAILED=1; }
wait $CODEX_PID  || { echo "  ! codex exited nonzero (see $OUT/codex.err)";  FAILED=1; }

for f in "$OUT/claude.md" "$OUT/codex.md"; do
  [[ -s "$f" ]] || { echo "error: $f is empty - cannot adjudicate" >&2; exit 1; }
done

echo "==> Adjudicating"

claude -p "Two security analysts independently reviewed the same evidence and did
not see each other's work. Adjudicate.

Do not average them and do not split the difference. Where they disagree, decide
which one is actually supported by the evidence and say why the other went wrong.
If neither did enough to justify its verdict, say UNPROVEN.

--- ANALYST A (Claude) ---
$(cat "$OUT/claude.md")

--- ANALYST B (Codex) ---
$(cat "$OUT/codex.md")

Output:
## AGREEMENT
Where they converged, and whether the convergence is meaningful or both made
the same assumption.
## DISAGREEMENT
Each conflict, and which side the evidence supports.
## FINAL VERDICT
CONFIRMED / LIKELY / UNPROVEN / NOT-A-FINDING, with confidence and the single
strongest piece of supporting evidence.
## NEXT CHECK
The one test that would most cheaply resolve the remaining uncertainty." \
  --add-dir "$EVIDENCE" \
  --permission-mode plan \
  > "$OUT/verdict.md" 2> "$OUT/verdict.err" \
  || { echo "  ! adjudication failed (see $OUT/verdict.err)"; FAILED=1; }

echo
sed -n '1,60p' "$OUT/verdict.md" 2>/dev/null || true
echo
echo "==> Full output in $OUT/  (claude.md, codex.md, verdict.md)"
exit $FAILED
