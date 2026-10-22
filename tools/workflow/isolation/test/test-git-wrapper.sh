#!/usr/bin/env bash
# Self-contained, dependency-free test harness for
# tools/workflow/isolation/git-wrapper.sh (workflow/isolation.md section 8).
#
# Runs the wrapper against a real scratch git repo, with GIT_WRAPPER_REAL_BIN
# pointed at the real `git` on this host -- same "actually run it" testing
# convention as tools/workflow/test/test-workflow.sh, not a mock. The
# wrapper itself only ever runs inside a Linux container in production, but
# its logic is pure POSIX shell and is exercised identically here.
#
# Usage: bash tools/workflow/isolation/test/test-git-wrapper.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
WRAPPER="${REPO_ROOT}/tools/workflow/isolation/git-wrapper.sh"
REAL_GIT="$(command -v git)"

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

# Sets up a fresh scratch git repo at $1, with a "main" branch and an extra
# "task/t1" branch pointer (never checked out -- checkout is restricted).
new_scratch() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  (
    cd "$dir"
    "$REAL_GIT" init -q
    "$REAL_GIT" config user.email test@test.com
    "$REAL_GIT" config user.name test
    echo "initial" > README.md
    "$REAL_GIT" add README.md
    "$REAL_GIT" commit -q -m init
    "$REAL_GIT" branch -m main 2>/dev/null || true
    "$REAL_GIT" branch task/t1
  )
}

gw() {
  local dir="$1"; shift
  (cd "$dir" && GIT_WRAPPER_REAL_BIN="$REAL_GIT" bash "$WRAPPER" "$@")
}

echo "=== tools/workflow/isolation/test/test-git-wrapper.sh ==="
echo

SCR="$(mktemp -d)"; new_scratch "$SCR"

out=$(gw "$SCR" status --porcelain 2>&1); code=$?
assert_eq "01 status passes through" "0" "$code"

out=$(gw "$SCR" diff 2>&1); code=$?
assert_eq "02 diff passes through" "0" "$code"

out=$(gw "$SCR" log --oneline 2>&1); code=$?
assert_eq "03 log passes through" "0" "$code"

echo "change" >> "$SCR/README.md"
gw "$SCR" add README.md >/dev/null 2>&1
out=$(gw "$SCR" status --porcelain)
assert_contains "04 add passes through and stages the file" "$out" "M  README.md"

out=$(gw "$SCR" commit -m "test commit" 2>&1); code=$?
assert_eq "05 commit passes through" "0" "$code"

echo "change2" >> "$SCR/README.md"
out=$(gw "$SCR" stash 2>&1); code=$?
assert_eq "06 stash passes through" "0" "$code"
out=$(gw "$SCR" stash pop 2>&1); code=$?
assert_eq "06b stash pop passes through" "0" "$code"

echo "change3" >> "$SCR/README.md"
out=$(gw "$SCR" restore README.md 2>&1); code=$?
assert_eq "07 restore passes through" "0" "$code"
out=$(cat "$SCR/README.md")
case "$out" in
  *change3*) fail "07b restore actually discarded the unstaged change" "found change3 still present" ;;
  *) pass "07b restore actually discarded the unstaged change" ;;
esac

echo "fileA" > "$SCR/a.txt"
(cd "$SCR" && "$REAL_GIT" add a.txt && "$REAL_GIT" commit -q -m "add a.txt")
echo "edited" >> "$SCR/a.txt"
out=$(gw "$SCR" checkout -- a.txt 2>&1); code=$?
assert_eq "08 checkout -- <path> (file restore form) passes through" "0" "$code"
out=$(cat "$SCR/a.txt")
assert_eq "08b checkout -- <path> actually restored the file" "fileA" "$out"

out=$(gw "$SCR" checkout main 2>&1); code=$?
assert_eq "09 checkout <ref> (branch switch form) is denied" "1" "$code"
assert_contains "10 denial explains why" "$out" "not permitted"

out=$(gw "$SCR" checkout -b new-branch 2>&1); code=$?
assert_eq "11 checkout -b <branch> is denied" "1" "$code"

out=$(gw "$SCR" push origin main 2>&1); code=$?
assert_eq "12 push is denied" "1" "$code"

out=$(gw "$SCR" fetch 2>&1); code=$?
assert_eq "13 fetch is denied" "1" "$code"

out=$(gw "$SCR" pull 2>&1); code=$?
assert_eq "14 pull is denied" "1" "$code"

out=$(gw "$SCR" remote -v 2>&1); code=$?
assert_eq "15 remote (even read-only -v) is denied" "1" "$code"

out=$(gw "$SCR" remote add evil https://evil.example/ 2>&1); code=$?
assert_eq "16 remote add is denied" "1" "$code"

out=$(gw "$SCR" switch main 2>&1); code=$?
assert_eq "17 switch is denied" "1" "$code"

out=$(gw "$SCR" branch 2>&1); code=$?
assert_eq "18 bare branch listing is denied (default-deny, not just -f/-D)" "1" "$code"

out=$(gw "$SCR" branch -D task/t1 2>&1); code=$?
assert_eq "19 branch -D is denied" "1" "$code"

out=$(gw "$SCR" rebase main 2>&1); code=$?
assert_eq "20 an unanticipated command (rebase) is denied by default, not allowed" "1" "$code"

out=$(GIT_WRAPPER_REAL_BIN="" bash "$WRAPPER" status 2>&1; echo "exit:$?")
assert_contains "21 a missing GIT_WRAPPER_REAL_BIN refuses loudly rather than guessing" "$out" "GIT_WRAPPER_REAL_BIN"

# core.hooksPath=/dev/null must be forced even on an allowed command, so a
# repo-tracked hooks convention can't run arbitrary code via `commit`.
mkdir -p "$SCR/.githooks"
cat > "$SCR/.githooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
echo "MALICIOUS HOOK RAN" > "$(dirname "$0")/../hook-ran.txt"
HOOK
chmod +x "$SCR/.githooks/pre-commit"
(cd "$SCR" && "$REAL_GIT" config core.hooksPath .githooks)
echo "trigger" >> "$SCR/README.md"
gw "$SCR" add README.md >/dev/null 2>&1
gw "$SCR" commit -m "should not run the tracked hook" >/dev/null 2>&1
if [ -f "$SCR/hook-ran.txt" ]; then
  fail "22 a repo-tracked core.hooksPath hook must not execute via an allowed commit" "hook-ran.txt was created"
else
  pass "22 a repo-tracked core.hooksPath hook must not execute via an allowed commit"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "Failed scenarios:"
  for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
