# Agent Guidelines for This Repository

This repository is a meta/tooling repo: it defines AI agent and skill files (`agents/*.agent.md`,
`claude-agents/*.md`, future `skills/`) and shell/PowerShell scripts that distribute them, plus
scripts that configure *other* repos for AI-assisted development. It is not itself a target
consumer of its own bootstrap output, and it contains no application code.

## The one constraint every script/config added here must follow

This repo's agent and skill files, and the scripts that install them, are distributed
**globally** — into `~/.claude`, `~/.copilot`, or wherever a user's tooling expects them — and
then invoked against *other* repositories. A script added here can never assume a fixed
relationship between where it is installed and the repo it is currently operating on.

Concretely: **always resolve the repo root via `git rev-parse --show-toplevel` from the
current working directory.** Never derive it relative to the script's own path
(`$0`, `$BASH_SOURCE`, `$MyInvocation.MyCommand.Path`, `__dirname`-equivalents, etc.) — that
path reflects where the script was *installed*, not which repo it was *invoked against*, and
those are routinely different directories once this repo's scripts are copied out to
`~/.claude` or `~/.copilot`.

`tools/ai-bootstrap/install.sh` / `install.ps1` and `tools/ai-bootstrap/bootstrap-ai-repo.sh` /
`bootstrap-ai-repo.ps1` already follow this rule and are the reference examples — read them
before adding a new script that needs to know "which repo am I operating on."

**Scope of this rule:** it applies to scripts that get distributed and then invoked against a
*target* repo — i.e. the scripts above. It does not apply to this repo's own dev-only test
harnesses under `tools/ai-bootstrap/test/`, which never leave this checkout and have a
different, legitimate need: a test harness must locate *itself* (and therefore the sibling
script it tests) regardless of which directory it's invoked from, which is exactly what
resolving via the script's own path is for. Those harnesses then independently point the
installer under test at disposable fixture repos via cwd — that cwd-based resolution is the
behavior being tested, and is unrelated to how the harness finds itself. Don't "fix" a test
harness's self-location to use cwd-based git resolution instead — that would make it fail
whenever it's invoked from outside the repo root, which is strictly worse.

See [tools/ai-bootstrap/README.md](./tools/ai-bootstrap/README.md) for what these scripts do.
