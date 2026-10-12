# Claude Code Guidelines for This Repository

This repository is a meta/tooling repo: it defines AI agent and skill files
(`agents/*.agent.md`, `claude-agents/*.md`, future `skills/`) and the scripts that distribute
them globally and configure other repos for AI-assisted development. It has no application
code and is not itself a target consumer of its own bootstrap output.

## The one constraint every script/config added here must follow

This repo's agent/skill files and installer scripts are copied out to `~/.claude`,
`~/.copilot`, or similar, and then run against *other* repositories. Never assume a fixed
relationship between a script's own install location and the repo it is invoked against.

**Always resolve the repo root via `git rev-parse --show-toplevel` from the current working
directory** — never relative to the script's own path (`$0`, `$BASH_SOURCE`,
`$MyInvocation.MyCommand.Path`, etc.). `tools/ai-bootstrap/install.sh` / `install.ps1` and
`tools/ai-bootstrap/bootstrap-ai-repo.sh` / `bootstrap-ai-repo.ps1` already follow this rule
and are the reference examples.

This applies to distributed scripts, not to this repo's own dev-only test harnesses under
`tools/ai-bootstrap/test/` — those legitimately resolve their own location to find the sibling
script they test, which is a different concern from the cwd-based resolution they then exercise
on that script.

See [AGENTS.md](./AGENTS.md) for the full explanation and
[tools/ai-bootstrap/README.md](./tools/ai-bootstrap/README.md) for what these scripts do.
