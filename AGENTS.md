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

See [tools/ai-bootstrap/README.md](./tools/ai-bootstrap/README.md) for what these scripts do.
