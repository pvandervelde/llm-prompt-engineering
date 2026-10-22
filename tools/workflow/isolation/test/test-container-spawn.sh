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

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "Failed scenarios:"
  for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
