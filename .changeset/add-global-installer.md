---
"llm-prompt-engineering": minor
---

Added a one-time global install step (`tools/ai-bootstrap/install.sh` and `install.ps1`) for
getting this repo's agent definitions onto your machine, distinct from bootstrapping a target
repo. Running the installer copies `agents/*.agent.md` to `~/.copilot/agents/`,
`claude-agents/*.md` to `~/.claude/agents/`, and (once any exist) `skills/<name>/` to both
`~/.claude/skills/<name>/` and `~/.copilot/skills/<name>/`. Set `$COPILOT_HOME` to install
Copilot agents somewhere other than `~/.copilot`. By default an existing destination file is
left untouched with a notice rather than overwritten; pass `--force` (bash) or `-Force`
(PowerShell) to overwrite. Both scripts also refuse to follow any symlink found in the source
tree, rejecting it with an error instead of dereferencing it, to close off a path by which a
planted symlink could copy an unrelated file into `~/.claude` or `~/.copilot`.
