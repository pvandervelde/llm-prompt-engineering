#!/bin/bash
# Self-contained, dependency-free end-to-end test harness for
# tools/ai-bootstrap/install.sh (issue #68).
#
# No bats, no external test framework - this repo validates its shell
# tooling by actually running it against a scratch environment, not by
# reading generated output or adopting a test-framework dependency.
#
# Usage: ./tools/ai-bootstrap/test/test-install.sh
# Exit code: 0 if every scenario passes, 1 otherwise.
#
# Scenario matrix (kept in sync with test-install.ps1 for contract parity
# across the bash and PowerShell implementations):
#
#   Tier 1 - specification / happy path
#     01 happy_path_creates_destination_dirs
#     02 agents_copied_to_copilot_with_exact_content
#     03 claude_agents_copied_to_claude_with_exact_content
#     04 destination_file_counts_match_source_exactly
#     05 exit_code_zero_on_success
#     06 copilot_home_override_redirects_destination
#     07 missing_skills_dir_skipped_silently
#     08 skills_dir_copied_to_both_targets_when_present
#     09 nested_destination_dirs_created_from_empty_home
#
#   Tier 2 - adversarial / boundary
#     10 no_force_skips_existing_file_without_overwrite
#     11 no_force_prints_notice_for_skipped_file
#     12 force_overwrites_existing_file
#     13 partial_preexisting_mixed_force_off
#     14 idempotent_rerun_without_force
#     15 idempotent_rerun_with_force_x3
#     16 byte_for_byte_stub_killer_all_targets
#     17 repo_root_resolved_from_cwd_not_script_location
#     18 invocation_outside_any_git_repo_fails_non_zero
#     19 no_writes_outside_destination_tree
#     20 source_repo_untouched_after_install
#     21 destination_path_with_spaces_is_handled
#
#   Tier 3 - QA adversarial audit (post-implementation, issue #68 follow-up)
#     22 dangling_symlink_in_agents_fails_loudly
#     23 symlink_in_skills_tree_rejected_without_leaking_content
#     24 destination_dir_is_symlink_writes_through_to_target
#     25 copilot_home_env_pointing_at_file_fails_loudly
#     26 weird_source_filenames_survive_byte_for_byte
#     27 source_repo_path_with_spaces_is_handled
#     28 symlink_escaping_source_tree_does_not_leak_external_content
#
#   Tier 4 - symlinked source *directories* (Copilot review follow-up,
#   issue #68, 2026-10-12): the Tier 3 fix only rejected symlinked
#   individual *files*; a symlinked source *directory* (agents/,
#   claude-agents/, skills/, or an individual skills/<name>/ entry) bypassed
#   that check entirely because `-d`/`find` dereference directories before
#   any per-file check ever runs.
#     29 agents_dir_itself_is_symlink_rejected_without_leaking_content
#     30 claude_agents_dir_itself_is_symlink_rejected_without_leaking_content
#     31 skills_root_itself_is_symlink_rejected_without_leaking_content
#     32 skill_entry_itself_is_symlink_rejected_without_leaking_content

set -uo pipefail
# Deliberately NOT using `set -e` globally: each scenario must be able to
# fail without aborting the rest of the suite.

# ---------------------------------------------------------------------------
# Locate the real repo + the script under test
# ---------------------------------------------------------------------------
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_REPO_ROOT="$(git -C "$THIS_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REAL_REPO_ROOT" ]; then
    echo "FATAL: cannot resolve the real repo root via git from $THIS_DIR" >&2
    exit 1
fi
INSTALL_SH="$REAL_REPO_ROOT/tools/ai-bootstrap/install.sh"

if [ ! -f "$INSTALL_SH" ]; then
    echo "NOTICE: $INSTALL_SH does not exist yet. Scenarios below are expected" >&2
    echo "        to fail until install.sh is implemented (TDD RED phase)." >&2
fi

# ---------------------------------------------------------------------------
# Scratch root
# ---------------------------------------------------------------------------
TMPBASE="${TMPDIR:-${TMP:-/tmp}}"
SCRATCH_ROOT="$(mktemp -d "$TMPBASE/install-sh-test.XXXXXX")"

cleanup() {
    rm -rf "$SCRATCH_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Counters / reporting
# ---------------------------------------------------------------------------
TESTS_RUN=0
TESTS_PASSED=0
FAILURES=()

note() { echo "    -> $1" >&2; }

run_case() {
    local name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    if "$name"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "[PASS] $name"
    else
        FAILURES+=("$name")
        echo "[FAIL] $name"
    fi
}

# ---------------------------------------------------------------------------
# Generic assertion helpers
# ---------------------------------------------------------------------------
assert_file_exists() {
    if [ ! -f "$1" ]; then
        note "expected file to exist: $1"
        return 1
    fi
    return 0
}

assert_file_absent() {
    if [ -f "$1" ]; then
        note "expected file to NOT exist: $1"
        return 1
    fi
    return 0
}

assert_dir_absent() {
    if [ -d "$1" ]; then
        note "expected directory to NOT exist: $1"
        return 1
    fi
    return 0
}

assert_files_equal() {
    # $1 = actual, $2 = expected/fixture
    if [ ! -f "$1" ]; then
        note "actual file missing: $1"
        return 1
    fi
    if ! cmp -s "$1" "$2"; then
        note "content mismatch between $1 and $2"
        return 1
    fi
    return 0
}

assert_file_content() {
    # $1 = path, $2 = expected exact content (no trailing newline assumed)
    if [ ! -f "$1" ]; then
        note "file missing: $1"
        return 1
    fi
    local actual
    actual="$(cat "$1")"
    if [ "$actual" != "$2" ]; then
        note "content mismatch in $1: expected [$2] got [$actual]"
        return 1
    fi
    return 0
}

count_files() {
    find "$1" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' '
}

# ---------------------------------------------------------------------------
# Fixture repo builders
# ---------------------------------------------------------------------------
init_fixture_git() {
    local dir="$1"
    git -C "$dir" init -q >/dev/null 2>&1
    git -C "$dir" config user.email "test@example.com" >/dev/null 2>&1
    git -C "$dir" config user.name "Test" >/dev/null 2>&1
    git -C "$dir" add -A >/dev/null 2>&1
    git -C "$dir" commit -q -m "fixture" >/dev/null 2>&1
}

populate_fixture_agents() {
    local dir="$1"
    mkdir -p "$dir/agents" "$dir/claude-agents"
    printf 'FIXTURE AGENT ALPHA CONTENT\n' > "$dir/agents/alpha.agent.md"
    printf 'FIXTURE AGENT BETA CONTENT\n'  > "$dir/agents/beta.agent.md"
    printf 'FIXTURE CLAUDE ALPHA CONTENT\n' > "$dir/claude-agents/alpha.md"
    printf 'FIXTURE CLAUDE BETA CONTENT\n'  > "$dir/claude-agents/beta.md"
}

make_fixture_repo() {
    local dir="$1"
    populate_fixture_agents "$dir"
    init_fixture_git "$dir"
}

make_fixture_repo_with_skills() {
    local dir="$1"
    populate_fixture_agents "$dir"
    mkdir -p "$dir/skills/demo-skill"
    printf 'FIXTURE SKILL MD\n' > "$dir/skills/demo-skill/SKILL.md"
    printf 'FIXTURE HELPER\n'   > "$dir/skills/demo-skill/helper.txt"
    init_fixture_git "$dir"
}

# try_symlink <target> <link>
# Attempts to create a real OS-level symlink (not a plain-copy fallback).
# On Windows, MSYS's `ln -s` silently falls back to copying the target
# instead of creating a symlink unless MSYS=winsymlinks:nativestrict is set
# AND the process holds symlink-creation privilege (Developer Mode or an
# elevated/admin token). Returns 0 and leaves a genuine symlink at <link>
# only when that privilege is available; returns 1 (and removes any partial
# artifact) otherwise, so callers can skip symlink-dependent scenarios with
# a clear notice on hosts that cannot exercise this path, rather than
# silently passing against a plain file copy that defeats the scenario's
# purpose.
try_symlink() {
    local target="$1" link="$2"
    if MSYS=winsymlinks:nativestrict ln -s "$target" "$link" 2>/dev/null && [ -L "$link" ]; then
        return 0
    fi
    rm -f "$link" 2>/dev/null || true
    return 1
}

FIXTURE_REPO="$SCRATCH_ROOT/fixture-repo"
FIXTURE_REPO_SKILLS="$SCRATCH_ROOT/fixture-repo-skills"
make_fixture_repo "$FIXTURE_REPO"
make_fixture_repo_with_skills "$FIXTURE_REPO_SKILLS"

# ---------------------------------------------------------------------------
# Invocation helper
# ---------------------------------------------------------------------------
# invoke_install <cwd> <home> [copilot_home|""] [extra args...]
invoke_install() {
    local cwd="$1"; local home="$2"; local copilot_home="$3"; shift 3
    (
        cd "$cwd" || exit 97
        export HOME="$home"
        if [ -n "$copilot_home" ]; then
            export COPILOT_HOME="$copilot_home"
        else
            unset COPILOT_HOME 2>/dev/null || true
        fi
        "$INSTALL_SH" "$@"
    )
    return $?
}

# ===========================================================================
# Tier 1 - specification / happy path
# ===========================================================================

happy_path_creates_destination_dirs() {
    local home="$SCRATCH_ROOT/t01/home"
    mkdir -p "$home"
    invoke_install "$FIXTURE_REPO" "$home" "" || { note "install exited non-zero"; return 1; }
    [ -d "$home/.copilot/agents" ] || { note "missing $home/.copilot/agents"; return 1; }
    [ -d "$home/.claude/agents" ] || { note "missing $home/.claude/agents"; return 1; }
    return 0
}

agents_copied_to_copilot_with_exact_content() {
    local home="$SCRATCH_ROOT/t02/home"
    mkdir -p "$home"
    invoke_install "$FIXTURE_REPO" "$home" "" >/dev/null 2>&1
    assert_files_equal "$home/.copilot/agents/alpha.agent.md" "$FIXTURE_REPO/agents/alpha.agent.md" || return 1
    assert_files_equal "$home/.copilot/agents/beta.agent.md"  "$FIXTURE_REPO/agents/beta.agent.md"  || return 1
    return 0
}

claude_agents_copied_to_claude_with_exact_content() {
    local home="$SCRATCH_ROOT/t03/home"
    mkdir -p "$home"
    invoke_install "$FIXTURE_REPO" "$home" "" >/dev/null 2>&1
    assert_files_equal "$home/.claude/agents/alpha.md" "$FIXTURE_REPO/claude-agents/alpha.md" || return 1
    assert_files_equal "$home/.claude/agents/beta.md"  "$FIXTURE_REPO/claude-agents/beta.md"  || return 1
    return 0
}

destination_file_counts_match_source_exactly() {
    local home="$SCRATCH_ROOT/t04/home"
    mkdir -p "$home"
    invoke_install "$FIXTURE_REPO" "$home" "" >/dev/null 2>&1
    local copilot_count claude_count
    copilot_count="$(count_files "$home/.copilot/agents")"
    claude_count="$(count_files "$home/.claude/agents")"
    if [ "$copilot_count" != "2" ]; then
        note "expected exactly 2 files in .copilot/agents, got $copilot_count"
        return 1
    fi
    if [ "$claude_count" != "2" ]; then
        note "expected exactly 2 files in .claude/agents, got $claude_count"
        return 1
    fi
    return 0
}

exit_code_zero_on_success() {
    local home="$SCRATCH_ROOT/t05/home"
    mkdir -p "$home"
    invoke_install "$FIXTURE_REPO" "$home" ""
    local code=$?
    if [ "$code" -ne 0 ]; then
        note "expected exit code 0, got $code"
        return 1
    fi
    return 0
}

copilot_home_override_redirects_destination() {
    local home="$SCRATCH_ROOT/t06/home"
    local copilot_home="$SCRATCH_ROOT/t06/custom-copilot"
    mkdir -p "$home" "$copilot_home"
    invoke_install "$FIXTURE_REPO" "$home" "$copilot_home" >/dev/null 2>&1
    assert_file_exists "$copilot_home/agents/alpha.agent.md" || return 1
    assert_file_exists "$copilot_home/agents/beta.agent.md" || return 1
    assert_dir_absent "$home/.copilot" || return 1
    return 0
}

missing_skills_dir_skipped_silently() {
    local home="$SCRATCH_ROOT/t07/home"
    mkdir -p "$home"
    local code
    invoke_install "$FIXTURE_REPO" "$home" ""
    code=$?
    if [ "$code" -ne 0 ]; then
        note "expected exit 0 when skills/ absent, got $code"
        return 1
    fi
    assert_dir_absent "$home/.claude/skills" || return 1
    assert_dir_absent "$home/.copilot/skills" || return 1
    return 0
}

skills_dir_copied_to_both_targets_when_present() {
    local home="$SCRATCH_ROOT/t08/home"
    mkdir -p "$home"
    invoke_install "$FIXTURE_REPO_SKILLS" "$home" "" >/dev/null 2>&1
    assert_files_equal "$home/.claude/skills/demo-skill/SKILL.md" "$FIXTURE_REPO_SKILLS/skills/demo-skill/SKILL.md" || return 1
    assert_files_equal "$home/.claude/skills/demo-skill/helper.txt" "$FIXTURE_REPO_SKILLS/skills/demo-skill/helper.txt" || return 1
    assert_files_equal "$home/.copilot/skills/demo-skill/SKILL.md" "$FIXTURE_REPO_SKILLS/skills/demo-skill/SKILL.md" || return 1
    assert_files_equal "$home/.copilot/skills/demo-skill/helper.txt" "$FIXTURE_REPO_SKILLS/skills/demo-skill/helper.txt" || return 1
    return 0
}

nested_destination_dirs_created_from_empty_home() {
    local home="$SCRATCH_ROOT/t09/home"
    mkdir -p "$home"
    # home is entirely empty: no .claude, no .copilot, not even parent dirs.
    if [ -n "$(ls -A "$home" 2>/dev/null)" ]; then
        note "precondition failed: home not empty"
        return 1
    fi
    invoke_install "$FIXTURE_REPO" "$home" "" >/dev/null 2>&1
    assert_file_exists "$home/.claude/agents/alpha.md" || return 1
    assert_file_exists "$home/.copilot/agents/alpha.agent.md" || return 1
    return 0
}

# ===========================================================================
# Tier 2 - adversarial / boundary
# ===========================================================================

no_force_skips_existing_file_without_overwrite() {
    local home="$SCRATCH_ROOT/t10/home"
    mkdir -p "$home/.copilot/agents"
    printf 'SENTINEL DO NOT OVERWRITE\n' > "$home/.copilot/agents/alpha.agent.md"
    invoke_install "$FIXTURE_REPO" "$home" "" >/dev/null 2>&1
    assert_file_content "$home/.copilot/agents/alpha.agent.md" "SENTINEL DO NOT OVERWRITE" || return 1
    return 0
}

no_force_prints_notice_for_skipped_file() {
    local home="$SCRATCH_ROOT/t11/home"
    mkdir -p "$home/.copilot/agents"
    printf 'SENTINEL DO NOT OVERWRITE\n' > "$home/.copilot/agents/alpha.agent.md"
    local output
    output="$(invoke_install "$FIXTURE_REPO" "$home" "" 2>&1)"
    if ! printf '%s' "$output" | grep -qiE 'skip|exist'; then
        note "expected some skip/exists notice in output, got: $output"
        return 1
    fi
    return 0
}

force_overwrites_existing_file() {
    local home="$SCRATCH_ROOT/t12/home"
    mkdir -p "$home/.copilot/agents"
    printf 'SENTINEL DO NOT OVERWRITE\n' > "$home/.copilot/agents/alpha.agent.md"
    invoke_install "$FIXTURE_REPO" "$home" "" --force >/dev/null 2>&1
    assert_files_equal "$home/.copilot/agents/alpha.agent.md" "$FIXTURE_REPO/agents/alpha.agent.md" || return 1
    return 0
}

partial_preexisting_mixed_force_off() {
    local home="$SCRATCH_ROOT/t13/home"
    mkdir -p "$home/.copilot/agents"
    printf 'SENTINEL ALPHA\n' > "$home/.copilot/agents/alpha.agent.md"
    # beta.agent.md intentionally absent
    invoke_install "$FIXTURE_REPO" "$home" "" >/dev/null 2>&1
    assert_file_content "$home/.copilot/agents/alpha.agent.md" "SENTINEL ALPHA" || return 1
    assert_files_equal "$home/.copilot/agents/beta.agent.md" "$FIXTURE_REPO/agents/beta.agent.md" || return 1
    return 0
}

idempotent_rerun_without_force() {
    local home="$SCRATCH_ROOT/t14/home"
    mkdir -p "$home"
    invoke_install "$FIXTURE_REPO" "$home" "" >/dev/null 2>&1
    local code
    invoke_install "$FIXTURE_REPO" "$home" "" >/dev/null 2>&1
    code=$?
    if [ "$code" -ne 0 ]; then
        note "second no-force run exited $code"
        return 1
    fi
    assert_files_equal "$home/.copilot/agents/alpha.agent.md" "$FIXTURE_REPO/agents/alpha.agent.md" || return 1
    return 0
}

idempotent_rerun_with_force_x3() {
    local home="$SCRATCH_ROOT/t15/home"
    mkdir -p "$home"
    local i
    for i in 1 2 3; do
        invoke_install "$FIXTURE_REPO" "$home" "" --force >/dev/null 2>&1
        local code=$?
        if [ "$code" -ne 0 ]; then
            note "force run #$i exited $code"
            return 1
        fi
        assert_files_equal "$home/.claude/agents/alpha.md" "$FIXTURE_REPO/claude-agents/alpha.md" || { note "mismatch after force run #$i"; return 1; }
    done
    return 0
}

byte_for_byte_stub_killer_all_targets() {
    local home="$SCRATCH_ROOT/t16/home"
    mkdir -p "$home"
    invoke_install "$FIXTURE_REPO_SKILLS" "$home" "" >/dev/null 2>&1
    assert_files_equal "$home/.copilot/agents/beta.agent.md" "$FIXTURE_REPO_SKILLS/agents/beta.agent.md" || return 1
    assert_files_equal "$home/.claude/agents/beta.md" "$FIXTURE_REPO_SKILLS/claude-agents/beta.md" || return 1
    assert_files_equal "$home/.claude/skills/demo-skill/SKILL.md" "$FIXTURE_REPO_SKILLS/skills/demo-skill/SKILL.md" || return 1
    assert_files_equal "$home/.copilot/skills/demo-skill/SKILL.md" "$FIXTURE_REPO_SKILLS/skills/demo-skill/SKILL.md" || return 1
    return 0
}

repo_root_resolved_from_cwd_not_script_location() {
    local home="$SCRATCH_ROOT/t17/home"
    mkdir -p "$home"
    # Invoke from a subdirectory deep inside the fixture repo, NOT its root,
    # and not anywhere near install.sh's own location. The installer must
    # still resolve FIXTURE_REPO as the source root via `git rev-parse
    # --show-toplevel`, not via its own script path.
    invoke_install "$FIXTURE_REPO/agents" "$home" "" >/dev/null 2>&1
    local code=$?
    if [ "$code" -ne 0 ]; then
        note "install exited $code when invoked from a nested cwd"
        return 1
    fi
    assert_files_equal "$home/.copilot/agents/alpha.agent.md" "$FIXTURE_REPO/agents/alpha.agent.md" || return 1
    assert_files_equal "$home/.claude/agents/alpha.md" "$FIXTURE_REPO/claude-agents/alpha.md" || return 1
    return 0
}

invocation_outside_any_git_repo_fails_non_zero() {
    local home="$SCRATCH_ROOT/t18/home"
    local no_git_cwd="$SCRATCH_ROOT/t18/no-git-here"
    mkdir -p "$home" "$no_git_cwd"
    invoke_install "$no_git_cwd" "$home" "" >/dev/null 2>&1
    local code=$?
    if [ "$code" -eq 0 ]; then
        note "expected non-zero exit when not inside a git repo, got 0"
        return 1
    fi
    return 0
}

no_writes_outside_destination_tree() {
    local home="$SCRATCH_ROOT/t19/home"
    local copilot_home="$SCRATCH_ROOT/t19/custom-copilot"
    mkdir -p "$home" "$copilot_home"
    invoke_install "$FIXTURE_REPO" "$home" "$copilot_home" >/dev/null 2>&1
    # Anything left over after excluding the two legitimate destination
    # trees means a stray write outside the resolved destination scope.
    local stray
    stray="$(find "$SCRATCH_ROOT/t19" -mindepth 1 \
        -not -path "${home}*" -not -path "${copilot_home}*" | sort)"
    if [ -n "$stray" ]; then
        note "stray files/dirs found outside destination trees: $stray"
        return 1
    fi
    return 0
}

source_repo_untouched_after_install() {
    local home="$SCRATCH_ROOT/t20/home"
    mkdir -p "$home"
    invoke_install "$FIXTURE_REPO" "$home" "" >/dev/null 2>&1
    local status
    status="$(git -C "$FIXTURE_REPO" status --porcelain)"
    if [ -n "$status" ]; then
        note "fixture repo is dirty after install: $status"
        return 1
    fi
    return 0
}

destination_path_with_spaces_is_handled() {
    local home="$SCRATCH_ROOT/t21/home dir with spaces"
    mkdir -p "$home"
    invoke_install "$FIXTURE_REPO" "$home" "" >/dev/null 2>&1
    local code=$?
    if [ "$code" -ne 0 ]; then
        note "install exited $code with a spaced home path"
        return 1
    fi
    assert_files_equal "$home/.copilot/agents/alpha.agent.md" "$FIXTURE_REPO/agents/alpha.agent.md" || return 1
    return 0
}

# ===========================================================================
# Tier 3 - QA adversarial audit (post-implementation, issue #68 follow-up)
# ===========================================================================

dangling_symlink_in_agents_fails_loudly() {
    local dir="$SCRATCH_ROOT/t22/repo"
    local home="$SCRATCH_ROOT/t22/home"
    mkdir -p "$dir" "$home"
    populate_fixture_agents "$dir"
    if ! try_symlink "does-not-exist.agent.md" "$dir/agents/dangling.agent.md"; then
        note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return 0
    fi
    init_fixture_git "$dir"
    invoke_install "$dir" "$home" "" >/dev/null 2>&1
    local code=$?
    if [ "$code" -eq 0 ]; then
        note "expected non-zero exit when a source glob match is a dangling symlink, got 0"
        return 1
    fi
    assert_files_equal "$home/.copilot/agents/alpha.agent.md" "$dir/agents/alpha.agent.md" || return 1
    assert_file_absent "$home/.copilot/agents/dangling.agent.md" || return 1
    return 0
}

symlink_in_skills_tree_rejected_without_leaking_content() {
    # Security regression test: a symlink inside skills/ - even one whose
    # target is a perfectly valid file - must be rejected, not followed.
    # Earlier drafts of this installer dereferenced the symlink and copied
    # its target's content verbatim into both ~/.claude and ~/.copilot,
    # which is exactly the vector a planted symlink could use to exfiltrate
    # an arbitrary file into a tree a future AI agent session reads back as
    # trusted content. See .llm/findings/global-installer-68.md.
    local dir="$SCRATCH_ROOT/t23/repo"
    local home="$SCRATCH_ROOT/t23/home"
    mkdir -p "$dir" "$home"
    populate_fixture_agents "$dir"
    mkdir -p "$dir/skills/demo-skill"
    printf 'REAL SKILL FILE\n' > "$dir/skills/demo-skill/real.txt"
    if ! try_symlink "real.txt" "$dir/skills/demo-skill/linked.txt"; then
        note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return 0
    fi
    init_fixture_git "$dir"
    local output
    output="$(invoke_install "$dir" "$home" "" 2>&1)"
    local code=$?
    if [ "$code" -eq 0 ]; then
        note "expected non-zero exit when skills/ contained a symlink, got 0"
        return 1
    fi
    if ! printf '%s' "$output" | grep -qiE 'symlink'; then
        note "expected a symlink-rejection notice in output, got: $output"
        return 1
    fi
    assert_file_absent "$home/.claude/skills/demo-skill/linked.txt" || return 1
    assert_file_absent "$home/.copilot/skills/demo-skill/linked.txt" || return 1
    # The real, non-symlinked sibling must still be installed correctly -
    # rejecting one symlinked entry must not abort the whole skill copy.
    assert_file_content "$home/.claude/skills/demo-skill/real.txt" "REAL SKILL FILE" || return 1
    assert_file_content "$home/.copilot/skills/demo-skill/real.txt" "REAL SKILL FILE" || return 1
    return 0
}

destination_dir_is_symlink_writes_through_to_target() {
    local home="$SCRATCH_ROOT/t24/home"
    local real_target="$SCRATCH_ROOT/t24/real-copilot-target"
    mkdir -p "$home" "$real_target"
    if ! try_symlink "$real_target" "$home/.copilot"; then
        note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return 0
    fi
    invoke_install "$FIXTURE_REPO" "$home" "" >/dev/null 2>&1
    local code=$?
    if [ "$code" -ne 0 ]; then
        note "install exited $code when the destination dir was a symlink"
        return 1
    fi
    assert_files_equal "$real_target/agents/alpha.agent.md" "$FIXTURE_REPO/agents/alpha.agent.md" || return 1
    [ -L "$home/.copilot" ] || { note "expected $home/.copilot to remain a symlink"; return 1; }
    return 0
}

copilot_home_env_pointing_at_file_fails_loudly() {
    local home="$SCRATCH_ROOT/t25/home"
    local copilot_home_file="$SCRATCH_ROOT/t25/copilot-home-as-a-file"
    mkdir -p "$home"
    printf 'NOT A DIRECTORY\n' > "$copilot_home_file"
    invoke_install "$FIXTURE_REPO" "$home" "$copilot_home_file" >/dev/null 2>&1
    local code=$?
    if [ "$code" -eq 0 ]; then
        note "expected non-zero exit when \$COPILOT_HOME points at a file, got 0"
        return 1
    fi
    assert_file_content "$copilot_home_file" "NOT A DIRECTORY" || return 1
    return 0
}

weird_source_filenames_survive_byte_for_byte() {
    local dir="$SCRATCH_ROOT/t26/repo"
    local home="$SCRATCH_ROOT/t26/home"
    mkdir -p "$dir/agents" "$dir/claude-agents" "$home"
    printf 'SPACE NAME\n' > "$dir/agents/with space.agent.md"
    printf 'UNICODE NAME\n' > "$dir/agents/café.agent.md"
    printf 'DASH NAME\n' > "$dir/agents/-leadingdash.agent.md"
    printf 'CLAUDE NORMAL\n' > "$dir/claude-agents/normal.md"
    init_fixture_git "$dir"
    invoke_install "$dir" "$home" "" >/dev/null 2>&1
    local code=$?
    if [ "$code" -ne 0 ]; then
        note "install exited $code with space/unicode/leading-dash source filenames"
        return 1
    fi
    assert_files_equal "$home/.copilot/agents/with space.agent.md" "$dir/agents/with space.agent.md" || return 1
    assert_files_equal "$home/.copilot/agents/café.agent.md" "$dir/agents/café.agent.md" || return 1
    assert_files_equal "$home/.copilot/agents/-leadingdash.agent.md" "$dir/agents/-leadingdash.agent.md" || return 1
    return 0
}

source_repo_path_with_spaces_is_handled() {
    local dir="$SCRATCH_ROOT/t27/repo with spaces in its path"
    local home="$SCRATCH_ROOT/t27/home"
    mkdir -p "$dir" "$home"
    populate_fixture_agents "$dir"
    init_fixture_git "$dir"
    invoke_install "$dir" "$home" "" >/dev/null 2>&1
    local code=$?
    if [ "$code" -ne 0 ]; then
        note "install exited $code with a spaced source repo path"
        return 1
    fi
    assert_files_equal "$home/.copilot/agents/alpha.agent.md" "$dir/agents/alpha.agent.md" || return 1
    return 0
}

symlink_escaping_source_tree_does_not_leak_external_content() {
    # Direct reproduction of the HIGH-severity finding from the security
    # audit: a symlink inside agents/ pointing OUTSIDE the repo entirely
    # (e.g. simulating ~/.ssh/id_rsa or /etc/passwd) must never have its
    # content copied into the destination tree.
    local dir="$SCRATCH_ROOT/t28/repo"
    local home="$SCRATCH_ROOT/t28/home"
    local secret="$SCRATCH_ROOT/t28/outside-repo-secret.txt"
    mkdir -p "$dir" "$home"
    populate_fixture_agents "$dir"
    printf 'SUPER-SECRET-SSH-KEY-CONTENT-DO-NOT-LEAK\n' > "$secret"
    if ! try_symlink "$secret" "$dir/agents/evil.agent.md"; then
        note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return 0
    fi
    init_fixture_git "$dir"
    invoke_install "$dir" "$home" "" >/dev/null 2>&1
    local code=$?
    if [ "$code" -eq 0 ]; then
        note "expected non-zero exit when a source symlink escapes the repo, got 0"
        return 1
    fi
    if grep -qr "SUPER-SECRET-SSH-KEY-CONTENT-DO-NOT-LEAK" "$home" 2>/dev/null; then
        note "SECURITY: external secret content leaked into the destination tree"
        return 1
    fi
    assert_file_absent "$home/.copilot/agents/evil.agent.md" || return 1
    # Legitimate sibling files must still install correctly.
    assert_files_equal "$home/.copilot/agents/alpha.agent.md" "$dir/agents/alpha.agent.md" || return 1
    return 0
}

# ===========================================================================
# Tier 4 - symlinked source *directories* (Copilot review follow-up, #68)
# ===========================================================================

agents_dir_itself_is_symlink_rejected_without_leaking_content() {
    # The existing per-file symlink check ([ -L "$src" ] in copy_file) never
    # even runs here: `[ -d "$src_dir" ]` in copy_glob dereferences a
    # symlinked agents/ directory, the glob expands straight through it,
    # and every resulting path is a *regular* file path, not a symlink.
    local dir="$SCRATCH_ROOT/t29/repo"
    local home="$SCRATCH_ROOT/t29/home"
    local external="$SCRATCH_ROOT/t29/external-agents-dir"
    mkdir -p "$dir" "$home" "$external"
    printf 'LEAKED-AGENTS-DIR-SECRET\n' > "$external/leaked.agent.md"
    populate_fixture_agents "$dir"
    rm -rf "$dir/agents"
    if ! try_symlink "$external" "$dir/agents"; then
        note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return 0
    fi
    init_fixture_git "$dir"
    local output
    output="$(invoke_install "$dir" "$home" "" 2>&1)"
    local code=$?
    if [ "$code" -eq 0 ]; then
        note "expected non-zero exit when agents/ itself is a symlink, got 0"
        return 1
    fi
    if ! printf '%s' "$output" | grep -qiE 'symlink'; then
        note "expected a symlink-rejection notice in output, got: $output"
        return 1
    fi
    if grep -qr "LEAKED-AGENTS-DIR-SECRET" "$home" 2>/dev/null; then
        note "SECURITY: external agents/ symlink target content leaked into the destination tree"
        return 1
    fi
    assert_dir_absent "$home/.copilot/agents" || return 1
    # Aggregate failure, not early abort: claude-agents/ (a sibling source
    # directory, not itself a symlink) must still install normally in the
    # same run.
    assert_files_equal "$home/.claude/agents/alpha.md" "$dir/claude-agents/alpha.md" || return 1
    assert_files_equal "$home/.claude/agents/beta.md" "$dir/claude-agents/beta.md" || return 1
    return 0
}

claude_agents_dir_itself_is_symlink_rejected_without_leaking_content() {
    local dir="$SCRATCH_ROOT/t30/repo"
    local home="$SCRATCH_ROOT/t30/home"
    local external="$SCRATCH_ROOT/t30/external-claude-agents-dir"
    mkdir -p "$dir" "$home" "$external"
    printf 'LEAKED-CLAUDE-AGENTS-DIR-SECRET\n' > "$external/leaked.md"
    populate_fixture_agents "$dir"
    rm -rf "$dir/claude-agents"
    if ! try_symlink "$external" "$dir/claude-agents"; then
        note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return 0
    fi
    init_fixture_git "$dir"
    local output
    output="$(invoke_install "$dir" "$home" "" 2>&1)"
    local code=$?
    if [ "$code" -eq 0 ]; then
        note "expected non-zero exit when claude-agents/ itself is a symlink, got 0"
        return 1
    fi
    if ! printf '%s' "$output" | grep -qiE 'symlink'; then
        note "expected a symlink-rejection notice in output, got: $output"
        return 1
    fi
    if grep -qr "LEAKED-CLAUDE-AGENTS-DIR-SECRET" "$home" 2>/dev/null; then
        note "SECURITY: external claude-agents/ symlink target content leaked into the destination tree"
        return 1
    fi
    assert_dir_absent "$home/.claude/agents" || return 1
    # Aggregate failure, not early abort: agents/ (a sibling source
    # directory, not itself a symlink) must still install normally.
    assert_files_equal "$home/.copilot/agents/alpha.agent.md" "$dir/agents/alpha.agent.md" || return 1
    assert_files_equal "$home/.copilot/agents/beta.agent.md" "$dir/agents/beta.agent.md" || return 1
    return 0
}

skills_root_itself_is_symlink_rejected_without_leaking_content() {
    local dir="$SCRATCH_ROOT/t31/repo"
    local home="$SCRATCH_ROOT/t31/home"
    local external="$SCRATCH_ROOT/t31/external-skills-root"
    mkdir -p "$dir" "$home" "$external"
    printf 'LEAKED-SKILLS-ROOT-SECRET\n' > "$external/leaked.txt"
    populate_fixture_agents "$dir"
    if ! try_symlink "$external" "$dir/skills"; then
        note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return 0
    fi
    init_fixture_git "$dir"
    local output
    output="$(invoke_install "$dir" "$home" "" 2>&1)"
    local code=$?
    if [ "$code" -eq 0 ]; then
        note "expected non-zero exit when skills/ itself is a symlink, got 0"
        return 1
    fi
    if ! printf '%s' "$output" | grep -qiE 'symlink'; then
        note "expected a symlink-rejection notice in output, got: $output"
        return 1
    fi
    if grep -qr "LEAKED-SKILLS-ROOT-SECRET" "$home" 2>/dev/null; then
        note "SECURITY: external skills/ symlink target content leaked into the destination tree"
        return 1
    fi
    assert_dir_absent "$home/.claude/skills" || return 1
    assert_dir_absent "$home/.copilot/skills" || return 1
    # Aggregate failure, not early abort: agents/ and claude-agents/ must
    # still install normally in the same run.
    assert_files_equal "$home/.copilot/agents/alpha.agent.md" "$dir/agents/alpha.agent.md" || return 1
    assert_files_equal "$home/.claude/agents/alpha.md" "$dir/claude-agents/alpha.md" || return 1
    return 0
}

skill_entry_itself_is_symlink_rejected_without_leaking_content() {
    # skills/ itself is a real directory; one individual entry underneath
    # it (skills/evil-skill) is a symlink to a directory entirely outside
    # the repo. A sibling, non-symlinked skill (skills/demo-skill) must
    # still install correctly in the same run.
    local dir="$SCRATCH_ROOT/t32/repo"
    local home="$SCRATCH_ROOT/t32/home"
    local external="$SCRATCH_ROOT/t32/external-evil-skill"
    mkdir -p "$dir" "$home" "$external"
    printf 'LEAKED-SKILL-ENTRY-SECRET\n' > "$external/leaked.txt"
    populate_fixture_agents "$dir"
    mkdir -p "$dir/skills/demo-skill"
    printf 'REAL SKILL FILE\n' > "$dir/skills/demo-skill/real.txt"
    if ! try_symlink "$external" "$dir/skills/evil-skill"; then
        note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return 0
    fi
    init_fixture_git "$dir"
    local output
    output="$(invoke_install "$dir" "$home" "" 2>&1)"
    local code=$?
    if [ "$code" -eq 0 ]; then
        note "expected non-zero exit when a skills/<name> entry itself is a symlink, got 0"
        return 1
    fi
    if ! printf '%s' "$output" | grep -qiE 'symlink'; then
        note "expected a symlink-rejection notice in output, got: $output"
        return 1
    fi
    if grep -qr "LEAKED-SKILL-ENTRY-SECRET" "$home" 2>/dev/null; then
        note "SECURITY: external skills/<name> symlink target content leaked into the destination tree"
        return 1
    fi
    assert_dir_absent "$home/.claude/skills/evil-skill" || return 1
    assert_dir_absent "$home/.copilot/skills/evil-skill" || return 1
    # Aggregate failure, not early abort: the real sibling skill must still
    # install correctly.
    assert_file_content "$home/.claude/skills/demo-skill/real.txt" "REAL SKILL FILE" || return 1
    assert_file_content "$home/.copilot/skills/demo-skill/real.txt" "REAL SKILL FILE" || return 1
    return 0
}

# ===========================================================================
# Run all scenarios
# ===========================================================================

run_case happy_path_creates_destination_dirs
run_case agents_copied_to_copilot_with_exact_content
run_case claude_agents_copied_to_claude_with_exact_content
run_case destination_file_counts_match_source_exactly
run_case exit_code_zero_on_success
run_case copilot_home_override_redirects_destination
run_case missing_skills_dir_skipped_silently
run_case skills_dir_copied_to_both_targets_when_present
run_case nested_destination_dirs_created_from_empty_home

run_case no_force_skips_existing_file_without_overwrite
run_case no_force_prints_notice_for_skipped_file
run_case force_overwrites_existing_file
run_case partial_preexisting_mixed_force_off
run_case idempotent_rerun_without_force
run_case idempotent_rerun_with_force_x3
run_case byte_for_byte_stub_killer_all_targets
run_case repo_root_resolved_from_cwd_not_script_location
run_case invocation_outside_any_git_repo_fails_non_zero
run_case no_writes_outside_destination_tree
run_case source_repo_untouched_after_install
run_case destination_path_with_spaces_is_handled

run_case dangling_symlink_in_agents_fails_loudly
run_case symlink_in_skills_tree_rejected_without_leaking_content
run_case destination_dir_is_symlink_writes_through_to_target
run_case copilot_home_env_pointing_at_file_fails_loudly
run_case weird_source_filenames_survive_byte_for_byte
run_case source_repo_path_with_spaces_is_handled
run_case symlink_escaping_source_tree_does_not_leak_external_content

run_case agents_dir_itself_is_symlink_rejected_without_leaking_content
run_case claude_agents_dir_itself_is_symlink_rejected_without_leaking_content
run_case skills_root_itself_is_symlink_rejected_without_leaking_content
run_case skill_entry_itself_is_symlink_rejected_without_leaking_content

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "============================================================"
echo "  $TESTS_PASSED / $TESTS_RUN scenarios passed"
echo "============================================================"

if [ "${#FAILURES[@]}" -gt 0 ]; then
    echo "FAILED scenarios:"
    for f in "${FAILURES[@]}"; do
        echo "  - $f"
    done
    exit 1
fi

exit 0
