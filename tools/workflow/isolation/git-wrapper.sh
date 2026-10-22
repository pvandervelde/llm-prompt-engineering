#!/usr/bin/env bash
# Git command wrapper enforcing workflow/isolation.md section 8's allow/deny
# policy inside an isolated container. Installed ahead of the real git
# binary on PATH (e.g. at /usr/local/bin/git) so every `git` invocation made
# by a containerized phase's agent goes through this first. Runs only inside
# the (always-Linux) container -- this has no PowerShell counterpart, unlike
# the host-side workflow.sh/.ps1 engine.
#
# GIT_WRAPPER_REAL_BIN must be set by the container image/entrypoint to the
# real git binary's absolute path (e.g. /usr/bin/git). This script never
# searches PATH for it -- doing so risks resolving back to this same wrapper
# if PATH ordering is ever misconfigured, which would recurse.
#
# Deliberately default-deny: only the subcommands explicitly named below pass
# through. An invocation with a global flag ahead of the subcommand (e.g.
# `git -C /elsewhere status`) is denied too, since $1 then isn't a recognized
# subcommand at all -- correct, not an oversight, for a wrapper whose whole
# point is confining git to the one mounted worktree.
set -euo pipefail

if [ -z "${GIT_WRAPPER_REAL_BIN:-}" ]; then
  echo "git-wrapper: GIT_WRAPPER_REAL_BIN is not set -- refusing to guess the real git binary's path" >&2
  exit 1
fi
if [ ! -x "$GIT_WRAPPER_REAL_BIN" ]; then
  echo "git-wrapper: GIT_WRAPPER_REAL_BIN ('${GIT_WRAPPER_REAL_BIN}') is not an executable file" >&2
  exit 1
fi

deny() {
  echo "git-wrapper: '$1' is not permitted inside an isolated phase (workflow/isolation.md section 8)" >&2
  exit 1
}

# core.hooksPath=/dev/null is forced on every invocation, allowed or not --
# a repo can point core.hooksPath at a tracked directory (a legitimate
# convention, e.g. ".githooks/"), which would otherwise let an allowed
# command like `commit` execute a hook script from the target repo's own
# tracked tree -- the same "adversarial content in the target repo" vector
# workflow/isolation.md section 1 already names. Harmless for the read-only
# commands below.
run() {
  exec "$GIT_WRAPPER_REAL_BIN" -c core.hooksPath=/dev/null "$@"
}

sub="${1:-}"

case "$sub" in
  ""|status|diff|log|show|blame|ls-files|add|commit|stash|restore)
    run "$@"
    ;;
  checkout)
    # Only the file-level restore form is permitted: `git checkout -- <path>...`.
    # Any other form (branch checkout, -b, a ref before --, etc.) is denied.
    if [ "${2:-}" = "--" ]; then
      run "$@"
    fi
    deny "git checkout (only 'git checkout -- <path>' is permitted; checking out a ref is not)"
    ;;
  push) deny "git push" ;;
  fetch) deny "git fetch" ;;
  pull) deny "git pull" ;;
  remote) deny "git remote" ;;
  switch) deny "git switch" ;;
  branch) deny "git branch" ;;
  *)
    deny "git ${sub}"
    ;;
esac
