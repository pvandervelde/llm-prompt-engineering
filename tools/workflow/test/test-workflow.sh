#!/usr/bin/env bash
# Self-contained, dependency-free end-to-end test harness for
# tools/workflow/workflow.sh (issue #55).
#
# No Pester/bats, no external test-framework dependency -- this repo
# validates its shell/PowerShell tooling by actually running it against a
# scratch git repo, not by reading the script or mocking its dependencies.
# Mirrors test-workflow.ps1 scenario-for-scenario for contract parity.
#
# Usage: bash tools/workflow/test/test-workflow.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORKFLOW_SH="${REPO_ROOT}/tools/workflow/workflow.sh"
PIPELINES_YML="${REPO_ROOT}/workflow/pipelines.yml"
LIB_DIR="${REPO_ROOT}/tools/workflow/lib"

PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL: $1 -- $2"; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$name"
  else
    fail "$name" "expected [$expected], got [$actual]"
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) pass "$name" ;;
    *) fail "$name" "expected output to contain [$needle], got [$haystack]" ;;
  esac
}

json_field() {
  # Minimal single-level field extractor for test assertions only. Handles
  # both quoted string values and bare literals (true/false/null/numbers).
  local json="$1" field="$2"
  printf '%s' "$json" | grep -o "\"${field}\":\"[^\"]*\"\|\"${field}\":[^,}]*" \
    | head -1 \
    | sed -E "s/\"${field}\"://" \
    | sed -E 's/^"(.*)"$/\1/'
}

# Sets up a fresh scratch git repo at $1 with workflow.sh + pipelines.yml copied in.
new_scratch() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir/workflow" "$dir/tools/workflow" "$dir/docs/spec" "$dir/.llm/spec-review"
  cp "$PIPELINES_YML" "$dir/workflow/pipelines.yml"
  cp -r "$LIB_DIR" "$dir/tools/workflow/lib"
  cp "$WORKFLOW_SH" "$dir/tools/workflow/workflow.sh"
  chmod +x "$dir/tools/workflow/workflow.sh"
  (
    cd "$dir"
    git init -q
    git config user.email test@test.com
    git config user.name test
    echo "initial" > README.md
    git add -A
    git commit -q -m init
    git branch -m main 2>/dev/null || true
  )
}

wf() {
  local dir="$1"; shift
  (cd "$dir" && bash tools/workflow/workflow.sh "$@")
}

echo "=== tools/workflow/test/test-workflow.sh ==="
echo

# --- Tier 1: happy path -----------------------------------------------------

echo "Tier 1 - happy path"

SCR="$(mktemp -d)"; new_scratch "$SCR"
out=$(wf "$SCR" init --task t1 --pipeline software)
assert_eq "01 init creates branch and returns first phase" "SPEC_REVIEW_GATE" "$(json_field "$out" phase)"
branch=$(cd "$SCR" && git branch --show-current)
assert_eq "02 init creates task/ branch from main" "task/t1" "$branch"
assert_eq "03 init returns first phase's agent name" "Spec Reviewer" "$(json_field "$out" agent)"

out=$(wf "$SCR" init --task t1 --pipeline software)
assert_eq "04 re-init on same task/branch reuses it (use)" "task/t1" "$(json_field "$out" branch)"

wf "$SCR" gate --phase SPEC_REVIEW_GATE --verdict CLEAR >/dev/null
out=$(wf "$SCR" next)
assert_contains "05 RED -> GREEN -> REFACTOR sequential advance (RED next)" "$out" '"phase":"RED"'
wf "$SCR" gate --phase RED --verdict done >/dev/null
out=$(wf "$SCR" next)
assert_contains "06 sequential advance (GREEN next)" "$out" '"phase":"GREEN"'
wf "$SCR" gate --phase GREEN --verdict done >/dev/null
out=$(wf "$SCR" next)
assert_contains "07 sequential advance (REFACTOR next)" "$out" '"phase":"REFACTOR"'
wf "$SCR" gate --phase REFACTOR --verdict CLEAN >/dev/null

out=$(wf "$SCR" next)
assert_contains "08 parallel stage returns both AUDIT and SECURITY" "$out" '"phase":"AUDIT"'
assert_contains "09 parallel stage returns both AUDIT and SECURITY (cont.)" "$out" '"phase":"SECURITY"'

wf "$SCR" gate --phase AUDIT --verdict CLEAR --actual 96 --target 95 >/dev/null
wf "$SCR" gate --phase SECURITY --verdict CLEAR >/dev/null
out=$(wf "$SCR" next)
assert_contains "10 both parallel phases done -> advances to DOCUMENT" "$out" '"phase":"DOCUMENT"'

wf "$SCR" gate --phase DOCUMENT --verdict done >/dev/null
out=$(wf "$SCR" next)
assert_contains "11 advances to VERIFY" "$out" '"phase":"VERIFY"'

out=$(wf "$SCR" gate --phase VERIFY --verdict PASS)
assert_eq "12 VERIFY PASS triggers onPass=open-pr" "open-pr" "$(json_field "$out" onPass)"
out=$(wf "$SCR" next)
assert_contains "13 pipeline reports complete after VERIFY" "$out" '"status":"complete"'

echo "- [ ] t1 Do the thing" > "$SCR/.llm/tasks.md"
out=$(wf "$SCR" complete --task t1)
assert_eq "14 complete marks task done" "true" "$(json_field "$out" taskMarked)"
assert_contains "15 complete rewrites tasks.md checkbox" "$(cat "$SCR/.llm/tasks.md")" "[x] t1"

SCR_INFRA="$(mktemp -d)"; new_scratch "$SCR_INFRA"
wf "$SCR_INFRA" init --task i1 --pipeline infrastructure >/dev/null
out=$(wf "$SCR_INFRA" gate --phase IMPLEMENT --verdict done --pipeline infrastructure)
assert_eq "16 infra pipeline: IMPLEMENT advances to SECURITY" "SECURITY" "$(json_field "$out" nextPhase)"
wf "$SCR_INFRA" gate --phase SECURITY --verdict CLEAR --pipeline infrastructure >/dev/null
out=$(wf "$SCR_INFRA" gate --phase VERIFY --verdict PASS --pipeline infrastructure)
assert_eq "17 infra pipeline: VERIFY PASS -> open-pr, no further phase" "open-pr" "$(json_field "$out" onPass)"

echo
echo "Tier 2 - adversarial / boundary"

SCR2="$(mktemp -d)"; new_scratch "$SCR2"
wf "$SCR2" init --task t1 --pipeline software >/dev/null
out=$(wf "$SCR2" init --task t2 --pipeline software 2>&1); code=$?
assert_eq "18 init on a different task's branch asks (exit 2)" "2" "$code"
assert_contains "19 wrong-task-branch reason surfaced" "$out" "wrong-task-branch"

(cd "$SCR2" && git switch -c some-other-branch -q)
out=$(wf "$SCR2" init --task t2 --pipeline software 2>&1); code=$?
assert_eq "20 init on an unrecognized branch asks (exit 2)" "2" "$code"
assert_contains "21 ambiguous-branch reason surfaced" "$out" "ambiguous-branch"
(cd "$SCR2" && git switch task/t1 -q)

wf "$SCR2" gate --phase SPEC_REVIEW_GATE --verdict CLEAR >/dev/null
wf "$SCR2" gate --phase RED --verdict done >/dev/null
wf "$SCR2" gate --phase GREEN --verdict done >/dev/null
wf "$SCR2" gate --phase REFACTOR --verdict CLEAN >/dev/null

out=$(wf "$SCR2" gate --phase AUDIT --verdict CLEAR --actual 10 --target 95)
assert_eq "22 gate never ADVANCEs on an unmet threshold" "FAIL" "$(json_field "$out" result)"
out=$(wf "$SCR2" next)
assert_contains "23 AUDIT still pending after failed threshold (did not silently advance)" "$out" '"phase":"AUDIT"'

out=$(wf "$SCR2" gate --phase AUDIT --verdict CLEAR --actual 96 --target 95)
assert_eq "24 gate advances once threshold is actually met" "ADVANCE" "$(json_field "$out" result)"

out=$(wf "$SCR2" gate --phase SECURITY --verdict BLOCKED --reason critical-finding)
assert_eq "25 gate PAUSEs on a recognized pauseWhen reason" "PAUSE" "$(json_field "$out" result)"
assert_contains "26 Blocking Issues populated on PAUSE" "$(cat "$SCR2/.llm/workflow-state.md")" "critical-finding"

out1=$(wf "$SCR2" next)
out2=$(wf "$SCR2" next)
assert_eq "27 resumability: next is idempotent across repeated calls" "$out1" "$out2"
assert_contains "28 resumability: paused phase (SECURITY) still returned" "$out1" '"phase":"SECURITY"'

wf "$SCR2" gate --phase SECURITY --verdict CLEAR >/dev/null
assert_contains "29 clearing the pause resets Blocking Issues to [None]" "$(cat "$SCR2/.llm/workflow-state.md")" "[None]"
out=$(wf "$SCR2" next)
assert_contains "30 pipeline resumes forward after the block clears" "$out" '"phase":"DOCUMENT"'

out=$(wf "$SCR2" gate --phase DOCUMENT --verdict done --reason not-a-real-reason 2>&1); code=$?
assert_eq "31 an unrecognized --reason is rejected" "1" "$code"

SCR3="$(mktemp -d)"; new_scratch "$SCR3"
echo "## Verdict" > "$SCR3/.llm/spec-review/2026-01-01-test.md"
echo "CLEAR" >> "$SCR3/.llm/spec-review/2026-01-01-test.md"
wf "$SCR3" init --task t3 --pipeline software >/dev/null
out=$(wf "$SCR3" next)
assert_contains "32 SPEC_REVIEW_GATE auto-skips when a fresh CLEAR report exists" "$out" '"phase":"RED"'

SCR4="$(mktemp -d)"; new_scratch "$SCR4"
echo "## Verdict" > "$SCR4/.llm/spec-review/2026-01-01-test.md"
echo "CLEAR" >> "$SCR4/.llm/spec-review/2026-01-01-test.md"
sleep 2
echo "newer spec" > "$SCR4/docs/spec/foo.md"
(cd "$SCR4" && git add docs/spec/foo.md && git commit -q -m "update spec")
wf "$SCR4" init --task t4 --pipeline software >/dev/null
out=$(wf "$SCR4" next)
assert_contains "33 SPEC_REVIEW_GATE does not skip when the report predates a spec change" "$out" '"phase":"SPEC_REVIEW_GATE"'

SCR5="$(mktemp -d)"; new_scratch "$SCR5"
wf "$SCR5" init --task sw --pipeline software >/dev/null
(cd "$SCR5" && git switch main -q)
wf "$SCR5" init --task in --pipeline infrastructure >/dev/null
out=$(wf "$SCR5" next 2>&1); code=$?
assert_eq "34 next with two active pipelines and no --pipeline errors" "1" "$code"
out=$(wf "$SCR5" next --pipeline software)
assert_contains "35 next --pipeline disambiguates correctly" "$out" '"phase":"SPEC_REVIEW_GATE"'

SCR6="$(mktemp -d)"; new_scratch "$SCR6"
wf "$SCR6" init --task t1 --pipeline software >/dev/null
out=$(wf "$SCR6" complete --task t1 2>&1); code=$?
assert_eq "36 complete refuses when the pipeline isn't finished" "1" "$code"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "Failed scenarios:"
  for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
