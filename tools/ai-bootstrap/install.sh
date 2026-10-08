#!/bin/bash
# Global installer for agent/skill distribution.
# Copies agents/*.agent.md -> ~/.copilot/agents/, claude-agents/*.md ->
# ~/.claude/agents/, and (if present) skills/<name>/ -> both
# ~/.claude/skills/<name>/ and ~/.copilot/skills/<name>/.
#
# Usage: ./install.sh [--force]
#
# Env overrides:
#   COPILOT_HOME - overrides the default ~/.copilot destination root.
#   HOME         - resolved at run time (standard POSIX $HOME).

set -uo pipefail
# Deliberately NOT using `set -e`: we want to attempt every copy and report
# a single aggregate failure at the end, rather than aborting on the first
# error.

# Parse arguments
FORCE=0
if [[ "${1:-}" == "--force" ]]; then
    FORCE=1
fi

# Resolve the repo root via git, from the current working directory. This
# script may be installed globally (e.g. a user's ~/.claude or ~/.copilot
# tools directory) and invoked against any repo as the current working
# directory, so the repo root must come from git, never from where this
# script itself happens to live (see issue #34).
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_notice() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Verify we're in a git repository
if [ -z "$ROOT" ]; then
    print_error "Not in a git repository. Run this from inside a git repository."
    exit 1
fi

# Resolve $HOME at run time
HOME_DIR="${HOME:-}"
if [ -z "$HOME_DIR" ]; then
    print_error "Unable to resolve \$HOME."
    exit 1
fi

COPILOT_HOME_DIR="${COPILOT_HOME:-$HOME_DIR/.copilot}"
CLAUDE_HOME_DIR="$HOME_DIR/.claude"

FAILED=0

# copy_file <src> <dst>
# Copies a single file, honoring --force skip/overwrite semantics and
# creating destination directories as needed.
copy_file() {
    local src="$1"
    local dst="$2"
    local dst_dir
    dst_dir="$(dirname "$dst")"

    # Security: never follow a symlink out of the source tree. A symlink
    # planted inside agents/, claude-agents/, or skills/ (valid or dangling)
    # could otherwise be used to read and exfiltrate an arbitrary file the
    # invoking user can access (e.g. ~/.ssh/id_rsa) into ~/.claude/skills/,
    # which a future AI agent session would read back as trusted content.
    # Reject every symlinked source entry explicitly rather than
    # dereferencing it, regardless of whether its target exists.
    if [ -L "$src" ]; then
        print_error "Refusing to follow symlink (security): $src"
        FAILED=1
        return 1
    fi

    if ! mkdir -p "$dst_dir"; then
        print_error "Failed to create directory: $dst_dir"
        FAILED=1
        return 1
    fi

    if [ -f "$dst" ] && [ "$FORCE" -ne 1 ]; then
        print_notice "Skipping existing file (use --force to overwrite): $dst"
        return 0
    fi

    if ! cp "$src" "$dst"; then
        print_error "Failed to copy $src -> $dst"
        FAILED=1
        return 1
    fi

    print_success "Copied $(basename "$src") -> $dst"
    return 0
}

# copy_glob <src_dir> <pattern> <dst_dir>
# Copies every file directly under src_dir matching pattern (non-recursive)
# into dst_dir via copy_file, creating dst_dir as needed. Skipped silently
# if src_dir does not exist.
copy_glob() {
    local src_dir="$1"
    local pattern="$2"
    local dst_dir="$3"
    local f

    [ -d "$src_dir" ] || return 0

    mkdir -p "$dst_dir"
    for f in "$src_dir"/$pattern; do
        # [ -e ] alone would also filter out a symlinked glob match (since
        # -e dereferences and a broken symlink's target doesn't exist),
        # making the installer silently skip it with no notice. Also accept
        # [ -L ] so every symlink (valid or dangling) reaches copy_file,
        # which explicitly rejects symlinked sources (security: never
        # dereference a source-tree symlink - see copy_file) instead of the
        # entry vanishing with no notice at all.
        [ -e "$f" ] || [ -L "$f" ] || continue
        copy_file "$f" "$dst_dir/$(basename "$f")"
    done
}

# copy_tree <src_dir> <dst_dir>
# Recursively copies every file under src_dir into dst_dir, preserving the
# relative directory structure, applying the same --force semantics to each
# file via copy_file.
copy_tree() {
    local src_dir="$1"
    local dst_dir="$2"
    local file rel

    while IFS= read -r -d '' file; do
        rel="${file#"$src_dir"/}"
        copy_file "$file" "$dst_dir/$rel"
    done < <(find "$src_dir" \( -type f -o -type l \) -print0)
    # Deliberately NOT `find -L ... -type f`: that would silently *dereference*
    # a valid symlink (defeating the security rejection in copy_file, which
    # never even sees it as a symlink) while also silently dropping a broken
    # one from the result set entirely (no copy attempt, no notice). Matching
    # by the entry's own type (-type l) regardless of target validity means
    # every symlinked entry reaches copy_file, which explicitly rejects it.
}

echo "Installing agents and skills..."

# ----------------------------------------------------------------------------
# Copilot agents: agents/*.agent.md -> $COPILOT_HOME_DIR/agents/
# ----------------------------------------------------------------------------
copy_glob "$ROOT/agents" "*.agent.md" "$COPILOT_HOME_DIR/agents"

# ----------------------------------------------------------------------------
# Claude agents: claude-agents/*.md -> $CLAUDE_HOME_DIR/agents/
# ----------------------------------------------------------------------------
copy_glob "$ROOT/claude-agents" "*.md" "$CLAUDE_HOME_DIR/agents"

# ----------------------------------------------------------------------------
# Skills: skills/<name>/ -> both $CLAUDE_HOME_DIR/skills/<name>/ and
# $COPILOT_HOME_DIR/skills/<name>/, unchanged. Skipped silently if skills/
# does not exist in the repo.
# ----------------------------------------------------------------------------
if [ -d "$ROOT/skills" ]; then
    for skill_path in "$ROOT"/skills/*/; do
        [ -d "$skill_path" ] || continue
        skill_path="${skill_path%/}"
        skill_name="$(basename "$skill_path")"
        copy_tree "$skill_path" "$CLAUDE_HOME_DIR/skills/$skill_name"
        copy_tree "$skill_path" "$COPILOT_HOME_DIR/skills/$skill_name"
    done
fi

if [ "$FAILED" -ne 0 ]; then
    print_error "Install completed with errors."
    exit 1
fi

print_success "Install complete."
exit 0
