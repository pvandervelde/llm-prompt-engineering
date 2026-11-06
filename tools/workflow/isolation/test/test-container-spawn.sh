#!/usr/bin/env bash
# Self-contained test harness for the container-spawn primitives in
# tools/workflow/workflow.sh (isolation_spawn_container,
# isolation_container_runtime, isolation_plain_image_ref -- workflow/
# isolation.md sections 3/10, piece 4 of the run-isolated implementation).
#
# Unlike tools/workflow/test/test-workflow.sh, this REQUIRES a real
# container runtime (Podman or Docker) and actually spawns containers --
# kept as its own file, and not run as part of the main engine suite, so
# that suite stays dependency-free (workflow/isolation.md sections 7/11:
# a container runtime is only needed by repos/tasks that opt into
# isolation, never by this tooling's own development/CI).
#
# Usage: bash tools/workflow/isolation/test/test-container-spawn.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
WORKFLOW_SH="${REPO_ROOT}/tools/workflow/workflow.sh"
GIT_WRAPPER="${REPO_ROOT}/tools/workflow/isolation/git-wrapper.sh"

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

# Sets up a fresh scratch git repo at $1, with the git wrapper copied into
# it at the same relative path isolation_spawn_container expects to find
# it (<root>/tools/workflow/isolation/git-wrapper.sh) -- mirrors how this
# repo's own distribution model copies tooling out to a target repo, and
# keeps this test from ever mounting (or writing into) the real
# development checkout.
new_scratch() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir/tools/workflow/isolation"
  cp "$GIT_WRAPPER" "$dir/tools/workflow/isolation/git-wrapper.sh"
  (
    cd "$dir"
    git init -q
    git config user.email test@test.com
    git config user.name test
    echo "initial" > README.md
    git add -A
    git commit -q -m init
  )
}

echo "=== tools/workflow/isolation/test/test-container-spawn.sh ==="
echo

if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
  echo "SKIP: neither docker nor podman is installed on this host -- nothing to test"
  exit 0
fi

# Safe to source now that workflow.sh guards its own main() call behind a
# direct-execution check -- see the bottom of that file.
# shellcheck source=../../workflow.sh
source "$WORKFLOW_SH"
# workflow.sh's own `set -euo pipefail` persists into this shell once
# sourced -- reset to this test file's intended semantics (no errexit;
# an expected nonzero return from e.g. isolation_plain_image_ref's
# refusal-path scenarios must not abort the whole suite).
set -uo pipefail
set +e

echo "Image spec translation"

out=$(isolation_plain_image_ref "image:rust:1-slim")
assert_eq "01 image: spec strips to a plain reference" "rust:1-slim" "$out"

out=$(isolation_plain_image_ref "build:Dockerfile:." 2>&1); code=$?
assert_eq "02 build: spec is refused (not yet implemented), not silently mishandled" "1" "$code"
assert_contains "03 the refusal names what's missing" "$out" "not yet implemented"

out=$(isolation_plain_image_ref "garbage" 2>&1); code=$?
assert_eq "04 an unrecognized spec is refused" "1" "$code"

echo
echo "Container spawn (real container, requires docker/podman)"

SCR="$(mktemp -d)"; new_scratch "$SCR"

out=$(isolation_spawn_container "$SCR" "alpine/git:latest" "git status --porcelain" 2>&1); code=$?
assert_eq "05 a basic spawn against a real scratch repo succeeds" "0" "$code"

out=$(isolation_spawn_container "$SCR" "alpine/git:latest" "which git" 2>&1)
assert_contains "06 the git wrapper is on PATH ahead of the real binary" "$out" "/usr/local/bin/git"

out=$(isolation_spawn_container "$SCR" "alpine/git:latest" "git push" 2>&1); code=$?
assert_eq "07 a denied git command's exit code propagates out" "1" "$code"
assert_contains "08 the denial message is visible in the spawn's output" "$out" "not permitted"

out=$(isolation_spawn_container "$SCR" "alpine/git:latest" "git log --oneline -1" 2>&1); code=$?
assert_eq "09 an allowed read-only command still succeeds" "0" "$code"

SENTINEL="isolation-spawn-test-$$"
isolation_spawn_container "$SCR" "alpine/git:latest" "echo '${SENTINEL}' > /workspace/written-from-container.txt" >/dev/null 2>&1
if [ -f "${SCR}/written-from-container.txt" ] && grep -q "$SENTINEL" "${SCR}/written-from-container.txt"; then
  pass "10 the workspace mount is really read-write against the scratch repo"
else
  fail "10 the workspace mount is really read-write against the scratch repo" "file not found or content mismatch"
fi

out=$(isolation_spawn_container "$SCR" "alpine/git:latest" "cat /etc/hostname 2>&1; ls /root 2>&1 | head -1" 2>&1); code=$?
assert_eq "11 a plain-filesystem command inside the container still succeeds (confinement is about host paths, not the container's own rootfs)" "0" "$code"

echo
echo "Network policy (SNI-filtered proxy sidecar, section 9 -- real network traffic, slower)"

out=$(isolation_spawn_container "$SCR" "curlimages/curl:latest" \
  "curl -sS -m 15 -o /dev/null -w 'HTTP %{http_code}' https://crates.io/" "rust" 2>&1); code=$?
assert_eq "12 an allowed SNI (crates.io, via the rust toolchain allowlist) is reachable through the proxy" "0" "$code"
assert_contains "13 a reached allowed host returns a real HTTP response, not a proxy error page" "$out" "HTTP"

out=$(isolation_spawn_container "$SCR" "curlimages/curl:latest" \
  "curl -sS -m 15 -o /dev/null -w 'HTTP %{http_code}' https://www.wikipedia.org/" "rust" 2>&1); code=$?
if [ "$code" -ne 0 ]; then
  pass "14 a disallowed SNI fails at the TLS layer (terminated after the peek), not with an HTTP response"
else
  fail "14 a disallowed SNI fails at the TLS layer (terminated after the peek), not with an HTTP response" "curl exited 0: $out"
fi

out=$(isolation_spawn_container "$SCR" "curlimages/curl:latest" \
  "curl -sS -m 10 --noproxy '*' -o /dev/null -w 'HTTP %{http_code}' https://crates.io/ 2>&1" "rust" 2>&1); code=$?
assert_contains "15 bypassing the proxy entirely still fails outright (no route exists, not just non-compliance)" "$out" "ould not resolve host"

# Plain HTTP is a separate code path from the ssl_bump/CONNECT logic above
# (section 9) -- found (2026-10-23) that without its own dstdomain gate,
# ANY plain-HTTP destination was allowed through unfiltered. Both cases
# of the proxy env vars matter here too: curl's httpoxy mitigation
# ignores uppercase-only HTTP_PROXY for exactly this traffic.
out=$(isolation_spawn_container "$SCR" "curlimages/curl:latest" \
  "curl -sS -m 10 -o /dev/null -w 'HTTP %{http_code}' http://deb.debian.org/debian/dists/bookworm/Release" "rust" 2>&1); code=$?
assert_eq "16 plain HTTP to an allowlisted host (deb.debian.org) is reachable through the proxy" "0" "$code"
assert_contains "17 a reached allowed plain-HTTP host returns a real response" "$out" "HTTP 2"

out=$(isolation_spawn_container "$SCR" "curlimages/curl:latest" \
  "curl -sS -m 10 -o /dev/null -w 'HTTP %{http_code}' http://neverssl.com/" "rust" 2>&1); code=$?
assert_contains "18 plain HTTP to a non-allowlisted host gets Squid's own denial, not a silent allow" "$out" "HTTP 403"

# End-to-end proof this whole mechanism actually supports the feature's
# real purpose: installing and running Claude Code itself inside the
# sandbox (section 7's credential exception, section 9's always-present
# allowlist entries). Confirmed manually (2026-10-23) before writing any
# of this; this scenario locks that proof in as a regression check. The
# slowest scenario in this suite by a wide margin (apt-get + a real
# ~100MB-class binary download) -- deliberately kept to one scenario, not
# several, to bound that cost.
out=$(isolation_spawn_container "$SCR" "debian:12-slim" \
  "apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq curl ca-certificates >/dev/null 2>&1 && curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 && export PATH=\"\$HOME/.local/bin:\$PATH\" && claude --version" \
  "rust" 2>&1); code=$?
assert_eq "19 Claude Code installs and runs successfully inside the sandbox, end to end" "0" "$code"
assert_contains "20 the installed claude actually reports a version, not a stale/empty success" "$out" "Claude Code"

# Regression check for a real bug found via an actual live-agent run
# (2026-11-06), not the automated suite: every default toolchain image
# except the .NET SDK one lacks git entirely, which silently defeats
# section 8's git-wrapper mount (GIT_WRAPPER_REAL_BIN=/usr/bin/git has
# nothing to exec). Runs the REAL isolation_build_entrypoint_command
# output's bootstrap lines (not a hand-copied reconstruction) against
# python:3.12-slim -- the exact image class that failed in practice --
# stopping before the `claude -p` line so this doesn't pay for a second
# Claude Code install on top of scenario 19/20's.
# Checks /usr/bin/git directly, bypassing the mounted wrapper on PATH --
# `git --version` would go through the wrapper instead, which correctly
# denies "version" as an unlisted subcommand (section 8's own, separately
# tested policy) and would fail this check for the wrong reason.
ENTRY_CMD=$(isolation_build_entrypoint_command "/isolation/input" "/isolation/output" "/isolation/run.jsonl" "/isolation/input/agents.json" "tester")
BOOTSTRAP_ONLY=$(printf '%s\n' "$ENTRY_CMD" | sed -n '1,/^claude -p/p' | sed '$d')
out=$(isolation_spawn_container "$SCR" "python:3.12-slim" \
  "${BOOTSTRAP_ONLY}
/usr/bin/git --version" 2>&1); code=$?
assert_eq "20b git is bootstrapped into an image that doesn't ship it (found via a real agent run, not guessed)" "0" "$code"
assert_contains "20c the bootstrapped git actually runs, not just exists" "$out" "git version"

echo
echo "Liveness polling and the hung status (section 3.4, piece 6)"

# isolation_run_phase is exercised directly against a cheap stub command,
# not a real `claude -p` call -- no ANTHROPIC_API_KEY is available in
# this dev environment, and a real call would spend real money. The real
# entrypoint STRING (isolation_build_entrypoint_command's output) is
# checked separately in tools/workflow/test/test-workflow.sh Tier 11,
# dependency-free since it's pure string construction. What's unique to
# this suite is the polling mechanism itself: liveness judged off the log
# file's own write activity, the two independent timeout tiers, and the
# kill-on-timeout behavior -- all of which need a real container.
# A dedicated, separately bind-mounted directory for the log -- NOT the
# same mount as /workspace -- matching how the real cmd_run_isolated flow
# bind-mounts .llm/isolation/{slug}/{phase}/ at /isolation, distinct from
# the worktree. The stub writes to the container-side path; isolation_run_phase
# polls the HOST-side path across the same bind mount.
LOG_DIR="$(mktemp -d)"
RUN_LOG="${LOG_DIR}/run.jsonl"

isolation_run_phase "$SCR" "alpine:3" \
  "echo line1 >> /logs/run.jsonl; sleep 1; echo line2 >> /logs/run.jsonl; exit 7" \
  "" "$LOG_DIR" "/logs" "$RUN_LOG" 30 60 > /tmp/run-phase-21.out 2>&1
read -r status21 code21 < /tmp/run-phase-21.out
assert_eq "21 a normal, quick completion reports done" "done" "$status21"
assert_eq "22 the container's real exit code is propagated" "7" "$code21"
assert_contains "23 the run log actually received the stub's output" "$(cat "$RUN_LOG" 2>/dev/null)" "line2"

rm -f "$RUN_LOG"
isolation_run_phase "$SCR" "alpine:3" \
  "echo line1 >> /logs/run.jsonl; sleep 25" \
  "" "$LOG_DIR" "/logs" "$RUN_LOG" 3 60 > /tmp/run-phase-24.out 2>&1
read -r status24 code24 < /tmp/run-phase-24.out
assert_eq "24 no new log activity within the liveness window reports hung, not a timeout-less hang" "hung" "$status24"
assert_eq "25 hung carries no meaningful exit code" "" "$code24"

rm -f "$RUN_LOG"
isolation_run_phase "$SCR" "alpine:3" \
  "i=0; while [ \$i -lt 60 ]; do echo \"line\$i\" >> /logs/run.jsonl; i=\$((i+1)); sleep 1; done" \
  "" "$LOG_DIR" "/logs" "$RUN_LOG" 60 5 > /tmp/run-phase-26.out 2>&1
read -r status26 code26 < /tmp/run-phase-26.out
assert_eq "26 staying live past the wall-clock ceiling still reports hung (the ceiling is absolute, not liveness-conditional)" "hung" "$status26"

rm -rf "$LOG_DIR"

echo
echo "run-isolated's full CLI wiring, end to end, against a stub entrypoint (section 6)"

# WORKFLOW_ISOLATION_TEST_ENTRYPOINT substitutes for the real `claude -p`
# command cmd_run_isolated would otherwise build -- same reasoning as
# above. This is the one place the full CLI path (materialize -> resolve
# image -> spawn -> poll -> read back verdict.json -> JSON response) is
# tested end to end, not just its component functions individually.
# This scratch repo needs BOTH halves other new_scratch helpers provide
# separately: workflow.sh/pipelines.yml/lib (what test-workflow.sh's
# new_scratch sets up, so `repo_root`/pipelines resolution works against
# this directory) and tools/workflow/isolation/git-wrapper.sh (what this
# file's own new_scratch sets up, so isolation_run_phase's mount check
# succeeds) -- the full CLI path needs both. Always invoked via the real
# repo's workflow.sh against this scratch dir as cwd, matching this
# project's own root-resolution rule (CLAUDE.md): `repo_root` resolves
# via `git rev-parse --show-toplevel` from cwd, never from the script's
# own path, so running the real script against a scratch cwd is the
# intended pattern, not a workaround.
SCR27="$(mktemp -d)"
rm -rf "$SCR27"
mkdir -p "$SCR27/workflow" "$SCR27/tools/workflow/isolation" "$SCR27/docs/spec" "$SCR27/.llm/spec-review"
cp "${REPO_ROOT}/workflow/pipelines.yml" "$SCR27/workflow/pipelines.yml"
cp -r "${REPO_ROOT}/tools/workflow/lib" "$SCR27/tools/workflow/lib"
cp "$GIT_WRAPPER" "$SCR27/tools/workflow/isolation/git-wrapper.sh"
(
  cd "$SCR27"
  git init -q
  git config user.email test@test.com
  git config user.name test
  echo "initial" > README.md
  git add -A
  git commit -q -m init
)
WF27="${REPO_ROOT}/tools/workflow/workflow.sh"
(cd "$SCR27" && bash "$WF27" init --task runiso1 --pipeline software >/dev/null)
(cd "$SCR27" && bash "$WF27" gate --phase SPEC_REVIEW_GATE --verdict CLEAR >/dev/null)

STUB_DONE='mkdir -p /isolation/output
echo "{\"verdict\":\"CLEAR\",\"findings\":[]}" > /isolation/output/verdict.json
echo "stub line" >> /isolation/run.jsonl
exit 0'
out=$(cd "$SCR27" && WORKFLOW_ISOLATION_TEST_ENTRYPOINT="$STUB_DONE" bash "$WF27" run-isolated --phase RED 2>&1); code=$?
assert_eq "27 the full run-isolated CLI returns success once the stub writes a verdict" "0" "$code"
assert_contains "28 the response reports status:done" "$out" '"status":"done"'
assert_contains "29 the agent's verdict.json fields are merged into the response, not nested" "$out" '"verdict":"CLEAR"'
assert_contains "30 outputRefs points at the phase's output directory" "$out" "RED/output/"

STUB_NO_VERDICT='echo "stub line" >> /isolation/run.jsonl
exit 0'
out=$(cd "$SCR27" && WORKFLOW_ISOLATION_TEST_ENTRYPOINT="$STUB_NO_VERDICT" bash "$WF27" run-isolated --phase GREEN 2>&1); code=$?
assert_eq "31 a clean exit with no verdict.json is a structured error, not a silent success" "1" "$code"
assert_contains "32 the error names the missing verdict.json, not a generic failure" "$out" "without writing output/verdict.json"

STUB_HUNG='sleep 15'
out=$(cd "$SCR27" && WORKFLOW_ISOLATION_TEST_ENTRYPOINT="$STUB_HUNG" WORKFLOW_ISOLATION_TEST_LIVENESS_TIMEOUT=3 WORKFLOW_ISOLATION_TEST_WALL_CLOCK_CEILING=30 bash "$WF27" run-isolated --phase REFACTOR 2>&1); code=$?
assert_eq "33 a hung phase is reported, not an error, and exits 0 (the Conductor must branch on status, not exit code)" "0" "$code"
assert_contains "34 the hung response carries the status" "$out" '"status":"hung"'
assert_contains "35 the hung response points at the real run.jsonl path for a human to inspect" "$out" "REFACTOR/run.jsonl"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "Failed scenarios:"
  for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
