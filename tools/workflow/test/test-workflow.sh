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
echo "Tier 3 - classify"

SCR7="$(mktemp -d)"; new_scratch "$SCR7"
cat > "$SCR7/.tech-decisions.yml" <<'TD'
classify:
  frontend: ["docs/spec/components/**", "docs/spec/ui/**"]
  backend: ["docs/spec/interfaces/**"]
  infrastructure: ["docs/spec/infrastructure/**", "docs/spec/modules/**"]
TD
cat > "$SCR7/.llm/tasks.md" <<'TASKS'
- [ ] t1 Implement auth
  - Context: docs/spec/interfaces/auth-operations.md
- [ ] t2 Build login form
  - Context: docs/spec/components/login-form.md
- [ ] t3 Nothing resolvable
  - Context: no spec path here
- [ ] t4 Conflicting signals
  - Context: docs/spec/interfaces/x.md and docs/spec/components/y.md
TASKS

out=$(wf "$SCR7" classify --task t1)
assert_eq "37 classify resolves backend from docs/spec/interfaces/" "backend" "$(json_field "$out" domain)"
out=$(wf "$SCR7" classify --task t2)
assert_eq "38 classify resolves frontend from docs/spec/components/" "frontend" "$(json_field "$out" domain)"
out=$(wf "$SCR7" classify --task t3)
assert_eq "39 classify with no resolvable path is ambiguous" "ambiguous" "$(json_field "$out" domain)"
out=$(wf "$SCR7" classify --task t4)
assert_eq "40 classify with conflicting signals is ambiguous (preserved from the old prose)" "ambiguous" "$(json_field "$out" domain)"
out=$(wf "$SCR7" classify --path docs/spec/infrastructure/network-vpc.md)
assert_eq "41 classify resolves infrastructure via direct --path" "infrastructure" "$(json_field "$out" domain)"
rm "$SCR7/.tech-decisions.yml"
out=$(wf "$SCR7" classify --task t1)
assert_eq "42 classify is ambiguous (not an error) when .tech-decisions.yml is absent" "ambiguous" "$(json_field "$out" domain)"

echo
echo "Tier 4 - context"

SCR8="$(mktemp -d)"; new_scratch "$SCR8"
mkdir -p "$SCR8/docs/spec"
cat > "$SCR8/docs/spec/assertions.md" <<'ASSERTIONS'
### ASSERT-0001: Login succeeds

```yaml
id: ASSERT-0001
module: auth
tags: [security]
given: a registered user with correct credentials
when: they submit the login form
then: a session token is issued
requirementRef: REQ-0001
```

### ASSERT-0002: Order total excludes tax

```yaml
id: ASSERT-0002
module: orders
given: a tax-exempt customer
when: an order total is calculated
then: tax is not applied
```
ASSERTIONS

out=$(wf "$SCR8" context --module auth)
assert_contains "43 context returns matching-module assertions" "$out" "ASSERT-0001"
assert_contains "43b context surfaces an assertion's requirementRef when present" "$out" "REQ-0001"
out=$(wf "$SCR8" context --module orders)
assert_contains "44 context scopes strictly to the requested module" "$out" "ASSERT-0002"
case "$out" in
  *ASSERT-0001*) fail "44b context must not leak other modules' assertions" "found ASSERT-0001 in orders query" ;;
  *) pass "44b context must not leak other modules' assertions" ;;
esac
out=$(wf "$SCR8" context --module orders --agent security-reviewer)
assert_eq "45 context filters to security-tagged only for security-reviewer" '{"module":"orders","assertions":[]}' "$out"
out=$(wf "$SCR8" context --module auth --agent security-reviewer)
assert_contains "46 security-reviewer still sees security-tagged assertions for its module" "$out" "ASSERT-0001"
out=$(wf "$SCR8" context --module nothing)
assert_eq "47 context returns an empty list for an unmatched module, not an error" '{"module":"nothing","assertions":[]}' "$out"
rm "$SCR8/docs/spec/assertions.md"
out=$(wf "$SCR8" context --module auth)
assert_eq "48 context is empty (not an error) when assertions.md doesn't exist" '{"module":"auth","assertions":[]}' "$out"

echo
echo "Tier 5 - tasks next"

SCR9="$(mktemp -d)"; new_scratch "$SCR9"
cat > "$SCR9/.llm/tasks.md" <<'TASKS'
- [ ] 1.0 Core shared types

```yaml
id: "1.0"
title: "Core shared types"
deps: []
criticality: domain_logic
specRefs: []
status: ready
domain: backend
```

- [ ] 1.1 Domain types

```yaml
id: "1.1"
title: "Domain types"
deps: ["1.0"]
criticality: domain_logic
specRefs: []
status: ready
domain: backend
```
TASKS

out=$(wf "$SCR9" tasks next)
assert_contains "49 tasks next returns the task with no unmet deps first" "$out" '"id":"1.0"'

# Mark 1.0 done via a targeted line edit (sed -i global would touch every status: line).
line=$(grep -n '^status: ready' "$SCR9/.llm/tasks.md" | head -1 | cut -d: -f1)
sed -i "${line}s/status: ready/status: done/" "$SCR9/.llm/tasks.md"
out=$(wf "$SCR9" tasks next)
assert_contains "50 tasks next advances once the dependency is done" "$out" '"id":"1.1"'

line=$(grep -n '^status: ready' "$SCR9/.llm/tasks.md" | head -1 | cut -d: -f1)
sed -i "${line}s/status: ready/status: done/" "$SCR9/.llm/tasks.md"
out=$(wf "$SCR9" tasks next)
assert_eq "51 tasks next reports none-ready once every task is done" '{"task":null,"reason":"none-ready"}' "$out"

cat > "$SCR9/.llm/tasks.md" <<'CYCLE'
- [ ] 2.0 A

```yaml
id: "2.0"
title: "A"
deps: ["2.1"]
criticality: domain_logic
specRefs: []
status: ready
domain: backend
```

- [ ] 2.1 B

```yaml
id: "2.1"
title: "B"
deps: ["2.0"]
criticality: domain_logic
specRefs: []
status: ready
domain: backend
```
CYCLE
out=$(wf "$SCR9" tasks next)
assert_eq "52 tasks next detects a dependency cycle instead of silently misordering" "cycle-detected" "$(json_field "$out" reason)"

rm "$SCR9/.llm/tasks.md"
out=$(wf "$SCR9" tasks next)
assert_eq "53 tasks next is a clean no-op (not an error) when tasks.md is absent" '{"task":null,"reason":"no-tasks-file"}' "$out"

SCR10="$(mktemp -d)"; new_scratch "$SCR10"
cat > "$SCR10/.llm/tasks.md" <<'CTASK'
- [ ] c1 Some task

```yaml
id: "c1"
title: "Some task"
deps: []
criticality: domain_logic
specRefs: []
status: ready
domain: backend
```
CTASK
wf "$SCR10" init --task c1 --pipeline software >/dev/null
wf "$SCR10" gate --phase SPEC_REVIEW_GATE --verdict CLEAR >/dev/null
wf "$SCR10" gate --phase RED --verdict done >/dev/null
wf "$SCR10" gate --phase GREEN --verdict done >/dev/null
wf "$SCR10" gate --phase REFACTOR --verdict CLEAN >/dev/null
wf "$SCR10" gate --phase AUDIT --verdict CLEAR >/dev/null
wf "$SCR10" gate --phase SECURITY --verdict CLEAR >/dev/null
wf "$SCR10" gate --phase DOCUMENT --verdict done >/dev/null
wf "$SCR10" gate --phase VERIFY --verdict PASS >/dev/null
wf "$SCR10" complete --task c1 >/dev/null
assert_contains "54 complete also flips the structured task record's status to done" "$(cat "$SCR10/.llm/tasks.md")" "status: done"
assert_contains "55 complete still flips the prose checkbox too" "$(cat "$SCR10/.llm/tasks.md")" "- [x] c1"

echo
echo "Tier 6 - risk-tier gate"

SCR11="$(mktemp -d)"; new_scratch "$SCR11"
wf "$SCR11" init --task r1 --pipeline software >/dev/null

out=$(wf "$SCR11" tier --files-changed 2)
assert_eq "56 tier computes minimal for <=3 files changed, no risk paths" "minimal" "$(json_field "$out" tier)"
assert_contains "57 tier writes Tier + Tier Reason into the active state file" "$(cat "$SCR11/.llm/workflow-state.md")" "**Tier:** minimal"

out=$(wf "$SCR11" tier --files-changed 8)
assert_eq "58 tier computes standard for a mid-range file count" "standard" "$(json_field "$out" tier)"

out=$(wf "$SCR11" tier --files-changed 20)
assert_eq "59 tier computes elevated for >15 files changed" "elevated" "$(json_field "$out" tier)"

out=$(wf "$SCR11" tier --files-changed 2 --untested-module auth)
assert_eq "60 tier computes elevated when a touched module has no existing tests" "elevated" "$(json_field "$out" tier)"

cat > "$SCR11/.tech-decisions.yml" <<'TD'
risk_paths: ["src/auth/**", "src/safety/**"]
TD
out=$(wf "$SCR11" tier --files-changed 2 --path src/auth/session.rs)
assert_eq "61 tier computes elevated when a touched path matches risk_paths, regardless of file count" "elevated" "$(json_field "$out" tier)"

out=$(wf "$SCR11" tier --files-changed 2 --override elevated)
assert_eq "62 human override up (minimal -> elevated) is accepted" "elevated" "$(json_field "$out" tier)"
assert_eq "63 an accepted override reports overridden=true" "true" "$(json_field "$out" overridden)"

out=$(wf "$SCR11" tier --files-changed 2 --path src/auth/session.rs --override minimal)
assert_eq "64 override cannot force a risk_paths-triggered elevated tier down" "elevated" "$(json_field "$out" tier)"
assert_contains "65 a rejected override explains the refusal" "$out" "cannot override down from elevated"
rm "$SCR11/.tech-decisions.yml"

SCR12="$(mktemp -d)"; new_scratch "$SCR12"
wf "$SCR12" init --task r2 --pipeline software >/dev/null
wf "$SCR12" tier --files-changed 2 >/dev/null
wf "$SCR12" gate --phase SPEC_REVIEW_GATE --verdict CLEAR >/dev/null
wf "$SCR12" gate --phase RED --verdict done >/dev/null
wf "$SCR12" gate --phase GREEN --verdict done >/dev/null
out=$(wf "$SCR12" gate --phase REFACTOR --verdict CLEAN)
assert_eq "66 gate on REFACTOR advances to AUDIT even under tier:minimal (the skip is lazy, applied only by next)" "AUDIT" "$(json_field "$out" nextPhase)"
out=$(wf "$SCR12" next)
assert_contains "67 next under tier:minimal returns only SECURITY (AUDIT auto-skipped)" "$out" '"phase":"SECURITY"'
case "$out" in
  *'"phase":"AUDIT"'*) fail "68 AUDIT must not appear in next's phases under tier:minimal" "found AUDIT in $out" ;;
  *) pass "68 AUDIT must not appear in next's phases under tier:minimal" ;;
esac
out=$(wf "$SCR12" gate --phase SECURITY --verdict CLEAR)
assert_eq "69 gate on SECURITY advances to DOCUMENT even under tier:minimal (the skip is lazy)" "DOCUMENT" "$(json_field "$out" nextPhase)"
out=$(wf "$SCR12" next)
assert_contains "70 next under tier:minimal returns VERIFY directly (DOCUMENT auto-skipped)" "$out" '"phase":"VERIFY"'
assert_contains "70b a skipOnTier skip leaves an audit-trail entry Verifier can recognize as exempt" "$(cat "$SCR12/.llm/workflow-state.md")" "AUDIT: skipped (tier: minimal, skipOnTier)"

echo
echo "Tier 7 - code-review fixes (multi-reason pauseWhen, init resume, skip audit trail)"

SCR13="$(mktemp -d)"; new_scratch "$SCR13"
wf "$SCR13" init --task p1 --pipeline software >/dev/null
wf "$SCR13" gate --phase SPEC_REVIEW_GATE --verdict CLEAR >/dev/null
wf "$SCR13" gate --phase RED --verdict done >/dev/null
wf "$SCR13" gate --phase GREEN --verdict done >/dev/null
wf "$SCR13" gate --phase REFACTOR --verdict CLEAN >/dev/null
out=$(wf "$SCR13" gate --phase AUDIT --verdict BLOCKED --reason safety-critical-survivor)
assert_eq "71 AUDIT pauses on the FIRST of its two pauseWhen reasons (safety-critical-survivor)" "PAUSE" "$(json_field "$out" result)"

SCR14="$(mktemp -d)"; new_scratch "$SCR14"
wf "$SCR14" init --task p2 --pipeline software >/dev/null
wf "$SCR14" gate --phase SPEC_REVIEW_GATE --verdict CLEAR >/dev/null
wf "$SCR14" gate --phase RED --verdict done >/dev/null
wf "$SCR14" gate --phase GREEN --verdict done >/dev/null
wf "$SCR14" gate --phase REFACTOR --verdict CLEAN >/dev/null
out=$(wf "$SCR14" gate --phase AUDIT --verdict BLOCKED --reason formal-counterexample)
assert_eq "72 AUDIT pauses on the SECOND of its two pauseWhen reasons (formal-counterexample)" "PAUSE" "$(json_field "$out" result)"

SCR15="$(mktemp -d)"; new_scratch "$SCR15"
wf "$SCR15" init --task p3 --pipeline software >/dev/null
wf "$SCR15" gate --phase SPEC_REVIEW_GATE --verdict CLEAR >/dev/null
wf "$SCR15" gate --phase RED --verdict done >/dev/null
out=$(wf "$SCR15" init --task p3 --pipeline software)
assert_eq "73 re-running init on an in-progress task resumes (returns the current phase, not the first)" "GREEN" "$(json_field "$out" phase)"
assert_contains "74 re-running init does not reset Current Phase in the state file" "$(cat "$SCR15/.llm/workflow-state.md")" "**Current Phase:** GREEN"

echo
echo "Tier 8 - isolation"

SCR16="$(mktemp -d)"; new_scratch "$SCR16"
wf "$SCR16" init --task iso1 --pipeline software >/dev/null
out=$(wf "$SCR16" next)
assert_contains "75 next reports isolation:direct for SPEC_REVIEW_GATE (no isolation key -> default)" "$out" '"phase":"SPEC_REVIEW_GATE","agent":"Spec Reviewer","isolation":"direct"'
assert_contains "76 next's isolation resolution is cached in the state file" "$(cat "$SCR16/.llm/workflow-state.md")" "SPEC_REVIEW_GATE: direct (repo default)"

wf "$SCR16" gate --phase SPEC_REVIEW_GATE --verdict CLEAR >/dev/null
out=$(wf "$SCR16" next)
assert_contains "77 next reports isolation:container for RED (pipelines.yml default)" "$out" '"phase":"RED","agent":"Tester","isolation":"container"'

SCR17="$(mktemp -d)"; new_scratch "$SCR17"
cat > "$SCR17/.tech-decisions.yml" <<'TD'
isolation:
  overrides:
    RED: direct
TD
wf "$SCR17" init --task iso2 --pipeline software >/dev/null
wf "$SCR17" gate --phase SPEC_REVIEW_GATE --verdict CLEAR >/dev/null
out=$(wf "$SCR17" next)
assert_contains "78 a repo-level .tech-decisions.yml override flips a phase's default" "$out" '"phase":"RED","agent":"Tester","isolation":"direct"'
assert_contains "78b the override's source is recorded, not just its mode" "$(cat "$SCR17/.llm/workflow-state.md")" "RED: direct (repo override)"

# Caching: once next has resolved+recorded a phase's mode, a LATER
# .tech-decisions.yml edit must not retroactively change it.
SCR18="$(mktemp -d)"; new_scratch "$SCR18"
wf "$SCR18" init --task iso3 --pipeline software >/dev/null
wf "$SCR18" gate --phase SPEC_REVIEW_GATE --verdict CLEAR >/dev/null
wf "$SCR18" next >/dev/null
cat > "$SCR18/.tech-decisions.yml" <<'TD'
isolation:
  overrides:
    RED: direct
TD
out=$(wf "$SCR18" next)
assert_contains "79 a cached isolation mode survives a later .tech-decisions.yml edit (not re-resolved)" "$out" '"phase":"RED","agent":"Tester","isolation":"container"'

# workflow isolation --override: strengthening is allowed.
SCR19="$(mktemp -d)"; new_scratch "$SCR19"
wf "$SCR19" init --task iso4 --pipeline software >/dev/null
out=$(wf "$SCR19" isolation --phase SECURITY --override container)
assert_eq "80 isolation --override strengthens a direct-by-default phase" "container" "$(json_field "$out" isolation)"
assert_eq "81 a successful strengthening override reports overridden=true" "true" "$(json_field "$out" overridden)"
assert_contains "82 a strengthening override is recorded in the state file" "$(cat "$SCR19/.llm/workflow-state.md")" "SECURITY: container (task override"

# workflow isolation --override: weakening is refused outright.
out=$(wf "$SCR19" isolation --phase RED --override direct)
assert_eq "83 isolation --override refuses to weaken a container-by-default phase" "container" "$(json_field "$out" isolation)"
assert_eq "84 a refused override reports overridden=false" "false" "$(json_field "$out" overridden)"
assert_contains "85 a refused override explains the refusal" "$out" "cannot downgrade RED below repo policy"
case "$(cat "$SCR19/.llm/workflow-state.md")" in
  *"RED: "*) fail "86 a refused override must not be written to the state file" "found a RED: line after refusal" ;;
  *) pass "86 a refused override must not be written to the state file" ;;
esac

# workflow isolation --override: requesting the mode already in effect is a no-op.
out=$(wf "$SCR19" isolation --phase RED --override container)
assert_eq "87 requesting the already-effective mode is a no-op (not an error)" "false" "$(json_field "$out" overridden)"
assert_eq "88 a no-op override still reports the correct isolation" "container" "$(json_field "$out" isolation)"

out=$(wf "$SCR19" isolation --phase RED --override bogus 2>&1); code=$?
assert_eq "89 an invalid --override value is rejected" "1" "$code"

SCR20="$(mktemp -d)"; new_scratch "$SCR20"
wf "$SCR20" init --task iso5 --pipeline infrastructure >/dev/null
out=$(wf "$SCR20" next --pipeline infrastructure)
assert_contains "90 infra pipeline: IMPLEMENT defaults to isolation:container" "$out" '"phase":"IMPLEMENT","agent":"Infrastructure Engineer","isolation":"container"'
wf "$SCR20" gate --phase IMPLEMENT --verdict done --pipeline infrastructure >/dev/null
out=$(wf "$SCR20" next --pipeline infrastructure)
assert_contains "91 infra pipeline: SECURITY defaults to isolation:direct" "$out" '"phase":"SECURITY","agent":"Security Reviewer","isolation":"direct"'

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "Failed scenarios:"
  for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
