# LLM Prompt Engineering

A meta/tooling repository for AI-assisted development: it defines a full roster of
specialized agents, a deterministic workflow engine that drives them through a TDD
pipeline, and the scripts that distribute both to your machine and bootstrap target repos
to use them.

## What You Get

### Multi-Agent Development Pipeline

- A full roster of specialized Claude Code (`claude-agents/`) and GitHub Copilot
  (`agents/`) agents covering both a software TDD pipeline (Architect → Interface
  Designer → Design Reviewer → Planner → Tester → Coder → Refactor → QA Engineer /
  Security Reviewer → Doc Writer → Verifier) and an infrastructure pipeline
  (Infrastructure Architect → Designer → Engineer → Security Reviewer → Verifier)
- A deterministic CLI engine (`tools/workflow/`, PowerShell and Bash) that drives phase
  sequencing, branch resolution, and gate thresholds from a declarative
  `workflow/pipelines.yml` — not prose an agent has to re-derive on every run
- Risk-tiered gating (`workflow tier`): skips the heaviest review phases on small, safe
  changes and makes elevated-risk changes impossible to downgrade past review
- One orchestrator agent, the **Conductor**, drives the whole pipeline end to end — see
  [claude-agents/README.md](./claude-agents/README.md) for the full agent graph

### Repository Analysis & Advanced Prompting (`prompts/`)

- Prompts that help AI assistants understand your codebase architecture, tech stack, and
  coding patterns
- GitHub Actions workflow generation for automated environment setup
- A multi-persona review system for evaluating ideas from different expert perspectives
- Conversation templates for maintaining context across AI sessions

## Install the Framework

This repository defines agent files for AI coding assistants — Copilot agents in
`agents/*.agent.md` and Claude Code agents in `claude-agents/*.md` — plus, in the future,
shared `skills/`. These need to land in your tool's global config directory before your
assistant can see them; the repo's own workspace is never the place they run from. This is
a **one-time, global** step, separate from bootstrapping a target repo (see below): run it
once from inside this repo's checkout to install the agent definitions onto your machine.

```bash
# Linux / macOS / Git Bash
./tools/ai-bootstrap/install.sh

# Windows PowerShell
.\tools\ai-bootstrap\install.ps1
```

This copies `agents/*.agent.md` to `~/.copilot/agents/`, `claude-agents/*.md` to
`~/.claude/agents/`, and (once any exist) `skills/<name>/` to both `~/.claude/skills/<name>/`
and `~/.copilot/skills/<name>/`. Existing destination files are left untouched unless you
pass `--force` (bash) or `-Force` (PowerShell). Set `$COPILOT_HOME` to install Copilot agents
somewhere other than `~/.copilot`. See [tools/ai-bootstrap/README.md](./tools/ai-bootstrap/README.md)
for details.

## Bootstrap a Repo

Separately, `tools/ai-bootstrap/bootstrap-ai-repo.*` configures *whatever repo you're
currently standing in* for AI-assisted development (`AGENTS.md`, git hooks,
`.tech-decisions.yml`, etc.) — a different job from installing this framework's own agent
definitions above. See [tools/ai-bootstrap/README.md](./tools/ai-bootstrap/README.md).

## Drive a Task Through the Agent Pipeline

Once the two steps above are done — agent definitions installed globally, target repo
bootstrapped — invoke the **Conductor** agent (Claude Code) or its Copilot equivalent and
give it a task. It does the rest: resolves the branch, works out which pipeline applies
(software or infrastructure), and drives every phase (test → implement → refactor →
audit/security → document → verify) by calling the workflow engine for every decision a
human would otherwise have to make by reading prose:

```bash
# The Conductor calls this directly — you normally never run it by hand.
# Shown here to make the contract explicit:
./tools/workflow/workflow.sh init --task 123 --pipeline software
./tools/workflow/workflow.sh next
./tools/workflow/workflow.sh gate --phase RED --verdict done
```

(`workflow.ps1` on Windows is a drop-in equivalent — same commands, same JSON output.)

Each phase dispatches a specialized subagent (Tester, Coder, Security Reviewer, ...) with
exactly the context it needs, pre-extracted from your spec and `.tech-decisions.yml`. See:

- [claude-agents/README.md](./claude-agents/README.md) — the full agent roster and pipeline graph
- [workflow/README.md](./workflow/README.md) — the pipeline schema (`pipelines.yml`) the engine reads
- [tools/workflow/README.md](./tools/workflow/README.md) — the `workflow` CLI's full command reference

## Project Structure

```text
├── claude-agents/          # Claude Code agent definitions (full TDD + infra pipeline)
├── agents/                 # GitHub Copilot agent definitions (*.agent.md mirrors)
├── workflow/                # pipelines.yml - the workflow engine's pipeline schema
├── prompts/                 # Reusable prompt templates
│   ├── conversation-continuation.prompt.md       # Context preservation templates
│   ├── copilot-setup-workflow.prompt.md          # GitHub Actions workflow generation
│   ├── group-personas.md                         # Multi-persona review system
│   ├── repository-description-instructions.prompt.md # Repository analysis
│   └── review-problem-with-group.prompt.md       # Group review templates
├── catalog/                 # Codebase catalog generator (symbol index for agents)
└── tools/                   # Automation scripts
    ├── ai-bootstrap/                   # Global installer + per-repo bootstrap scripts
    └── workflow/                       # The workflow CLI engine (workflow.sh / .ps1)
```

## Documentation

### Getting Started

- [Contributing Guidelines](./CONTRIBUTING.md) - How to add new agents, prompts, and tools

### Agent Pipeline

- [claude-agents/README.md](./claude-agents/README.md) - Full agent roster and pipeline graph (software + infrastructure)
- [workflow/README.md](./workflow/README.md) - Pipeline schema (`pipelines.yml`) reference
- [tools/workflow/README.md](./tools/workflow/README.md) - `workflow` CLI command reference
- [tools/ai-bootstrap/README.md](./tools/ai-bootstrap/README.md) - Global install + per-repo bootstrap scripts, including the `.tech-decisions.yml` blocks the engine reads

### Prompt Templates

- [Repository Analysis](./prompts/repository-description-instructions.prompt.md) - Analyze any codebase to generate instruction files
- [Workflow Generation](./prompts/copilot-setup-workflow.prompt.md) - Create GitHub Actions workflows for environment setup
- [Group Review](./prompts/review-problem-with-group.prompt.md) - Get feedback from multiple expert perspectives
- [Conversation Continuation](./prompts/conversation-continuation.prompt.md) - Maintain context across AI sessions

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md) for how this repository
is organized and how to add new agents, prompts, or tooling.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
