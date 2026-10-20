# Contributing to LLM Prompt Engineering

Thank you for your interest in contributing to this project! This guide will help you get started.

## Getting Started

1. Fork the repository
2. Clone your fork locally

## Project Structure

- **`claude-agents/`**: Claude Code agent definitions (full TDD + infrastructure pipeline)
- **`agents/`**: GitHub Copilot agent definitions (`*.agent.md` mirrors of `claude-agents/`)
- **`workflow/`**: `pipelines.yml` — the declarative pipeline schema the workflow engine reads
- **`tools/workflow/`**: The `workflow` CLI engine (PowerShell and Bash) that drives phase sequencing and gating
- **`tools/ai-bootstrap/`**: Global installer (`install.sh`/`.ps1`) and per-repo bootstrap scripts (`bootstrap-ai-repo.*`)
- **`prompts/`**: Reusable prompt templates for repository analysis and group review
- **`catalog/`**: Codebase catalog generator (symbol index for agents)

## Making Changes

### Adding or Changing an Agent

1. Claude Code agents live in `claude-agents/*.md`; their Copilot mirrors live in
   `agents/*.agent.md`. Keep both in sync when an agent's responsibilities or pipeline
   position change.
2. Update [claude-agents/README.md](./claude-agents/README.md) if you add a new agent or
   change the pipeline graph.

### Modifying the Workflow Engine

1. `tools/workflow/workflow.sh` and `workflow.ps1` must stay behaviorally identical —
   same commands, same JSON output.
2. Run the test harness under `tools/workflow/test/` before submitting.
3. Update `workflow/pipelines.yml` and [workflow/README.md](./workflow/README.md) if you
   change phase sequencing or gate thresholds.

### Modifying Bootstrap / Installer Scripts

1. Any script under `tools/ai-bootstrap/` may be installed globally and then invoked
   against an arbitrary target repo — **always resolve the repo root via
   `git rev-parse --show-toplevel` from the current working directory**, never relative to
   the script's own path. See [AGENTS.md](./AGENTS.md) for the full rationale.
2. Keep the `.sh` and `.ps1` variants behaviorally equivalent.
3. Test changes end-to-end against a scratch repo, not just by reading the generated
   output — see `tools/ai-bootstrap/test/` for the existing harness pattern.

### Adding New Prompts

1. Create a new markdown file in the `prompts/` directory
2. Use descriptive filenames that indicate the prompt's purpose
3. Include examples where helpful

## Testing

Before submitting changes:

1. If you touched `tools/workflow/` or `tools/ai-bootstrap/`, run their test suites
   (`tools/workflow/test/`, `tools/ai-bootstrap/test/`)
2. Verify any new or changed agent file still mirrors correctly between `agents/` and
   `claude-agents/`
3. Test any new prompts with your preferred LLM tool

## Submitting Changes

1. Create a meaningful commit message
2. Push to your fork
3. Create a pull request with:
   - Clear description of what you changed
   - Why the change is needed
   - Any testing you performed

## Questions?

If you have questions about contributing, please:

- Review existing agent, workflow, and prompt files for examples
- Open an issue for discussion

We appreciate your contributions!
