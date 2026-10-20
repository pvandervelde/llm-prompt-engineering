# AI-Assisted Development Bootstrap

This directory contains two distinct kinds of script, serving two distinct jobs:

- **`install.*`** — global, one-time: copies this repo's own agent/skill definitions onto
  your machine (`~/.claude`, `~/.copilot`), so your AI tools can see them. Run from inside
  this repo's checkout; where you run it from has no bearing on which repo gets configured.
- **`bootstrap-ai-repo.*`** — per-target-repo: configures *whatever repo you're currently
  standing in* for AI-assisted development (`AGENTS.md`, git hooks, `.tech-decisions.yml`,
  etc.). This is the one documented in most of the rest of this file.

## Install Agent/Skill Definitions (`install.sh` / `install.ps1`)

Installs this repo's agent and skill sources into the global locations your AI tools read
from:

- `agents/*.agent.md` -> `~/.copilot/agents/` (or `$COPILOT_HOME/agents/` if set)
- `claude-agents/*.md` -> `~/.claude/agents/`
- `skills/<name>/` (once any exist) -> both `~/.claude/skills/<name>/` and
  `~/.copilot/skills/<name>/`

```bash
# Linux / macOS / Git Bash
./tools/ai-bootstrap/install.sh
./tools/ai-bootstrap/install.sh --force   # overwrite existing destination files

# Windows PowerShell
.\tools\ai-bootstrap\install.ps1
.\tools\ai-bootstrap\install.ps1 -Force   # overwrite existing destination files
```

Without `--force`/`-Force`, a destination file that already exists is left alone and a
notice is printed instead of overwriting it. The repo root is always resolved via
`git rev-parse --show-toplevel` from the current working directory — never relative to the
script's own install path — so this works correctly whether you run it from a checkout or
from wherever it ends up installed. As a security measure, both scripts refuse to follow
any symlink found in the source tree (`agents/`, `claude-agents/`, or `skills/`); a symlinked
entry is rejected with an error rather than dereferenced, closing off a path by which a
planted symlink could cause an unrelated file to be copied into `~/.claude` or `~/.copilot`.

## Bootstrap a Target Repo (`bootstrap-ai-repo.sh` / `bootstrap-ai-repo.ps1`)

Choose your platform:

### Windows / PowerShell

```powershell
.\tools\ai-bootstrap\bootstrap-ai-repo.ps1
```

### Linux / macOS / Bash

```bash
./tools/ai-bootstrap/bootstrap-ai-repo.sh
```

### Force Overwrite Existing Files

```powershell
# PowerShell
.\tools\ai-bootstrap\bootstrap-ai-repo.ps1 -Force

# Bash
./tools/ai-bootstrap/bootstrap-ai-repo.sh --force
```

## What the Bootstrap Script Does

The bootstrap scripts automate the following setup steps:

### 1. AI Memory Structure

- Creates `docs/adr/` (Architecture Decision Records)
- Creates `docs/standards/` (Coding standards)
- Creates `.githooks/` (Git hooks)
- Generates `AGENTS.md` (AI agent guidelines)

### 2. Git Hooks

- Pre-commit: Format checks, linting, secrets detection
- Commit-msg: Conventional commit format validation
- Pre-push: Branch and history checks

### 3. Technology Decision Registry

- Creates `.tech-decisions.yml`
- Documents tech stack choices
- Tracks decision rationale

`.tech-decisions.yml` also carries several blocks read by the workflow engine
(`tools/workflow/`, see [tools/workflow/README.md](../workflow/README.md)) rather than by
a human or CI directly:

| Block | Read by | Purpose |
|---|---|---|
| `toolchains` | Conductor (`## Toolchain` context block) | Resolves abstract capabilities (test, mutation, fuzz, formal, ...) to concrete commands for the detected stack |
| `mutation_targets` | QA Engineer | Per-mutation-engine minimum score, keyed by the same criticality classes as `criticality` below — not comparable across engines, hence one block per engine |
| `criticality` | `workflow gate` (AUDIT phase), QA Engineer | Glob-maps module paths to a criticality class (`safety_critical`, `parser`, `domain_logic`, `api_boundary`, `adapter`); first match wins, unmapped paths default to `domain_logic` |
| `classify` | `workflow classify` | Glob-maps task-referenced paths to `frontend`/`backend`/`infrastructure`, replacing the hand-written domain-detection prose `tech-lead.md` and `planner.md` used to carry |
| `risk_paths` | `workflow tier` | Any path matching this list forces the task's risk tier to `elevated` — a hard rule a human cannot override down, unlike the other blocks above |

All five ship with the generic defaults (or, for `criticality`/`classify`/`risk_paths`,
empty/example globs) shown in the generated file's comments — customize the glob lists for
your own repo's directory layout; an empty or missing mapping is a valid, safe default
(`ambiguous`/`domain_logic`/no forced elevation), not an error.

### 4. Workflow Engine

- Copies `tools/workflow/workflow.sh`/`.ps1` + `lib/` and `workflow/pipelines.yml` into
  the target repo — the engine resolves both relative to *that* repo's own git root (see
  `tools/workflow/README.md`), so they have to actually live there, not just globally
- Skipped (per file, with a notice) if the destination already exists, same as
  `.tech-decisions.yml` — pass `--force`/`-Force` to re-sync after a framework update
- `conductor.md`/`conductor.agent.md` depend on this step; without it, `workflow <command>`
  has nothing to invoke in the bootstrapped repo

### 5. Task Tracking Setup (Optional)

- Creates `.llm/tasks.md` template
- Agents (Planner, Coder, Conductor, ...) read and parse this format directly
- Tasks are stored as Markdown checklist items

This script does not generate CI configuration. A repo is not assumed to be
hosted on GitHub, nor to be CI-less — pipeline gating (assertion coverage,
traceability, mutation score, etc.) is guidance for wiring into whatever CI
the repo already has, not a file this script writes for you.

## Task Tracking Details

### Task Tracking (.llm/tasks.md)

1. **Planner agent** creates/updates `.llm/tasks.md`
2. **Conductor** resolves the next ready task via `workflow tasks next` — the next task
   whose dependencies are satisfied in `.llm/tasks.md`'s dependency graph, not simply the
   first unchecked checkbox — and dispatches the **Coder agent** to execute it

**Markdown Format Example:**

```markdown
# Implementation Tasks

## Project Context
- Architecture: Hexagonal
- Testing: TDD with Jest

## Task List

- [ ] 1.0 Implement Core Types
  - Context: Foundation for all tasks
  - File: src/core/types.ts
  - [ ] 1.1 Implement Result<T, E> type
  - [ ] 1.2 Implement validation types
```

### Reading Tasks

Agents follow this process:

1. **Check for `.llm/tasks.md`**
   - If exists → parse Markdown format
   - If not → ask user to create it

## Files in This Directory

- **install.ps1** - PowerShell global installer (agent/skill definitions -> `~/.claude`, `~/.copilot`)
- **install.sh** - Bash global installer (agent/skill definitions -> `~/.claude`, `~/.copilot`)
- **bootstrap-ai-repo.ps1** - PowerShell bootstrap script (Windows) — configures a target repo
- **bootstrap-ai-repo.sh** - Bash bootstrap script (Linux/macOS) — configures a target repo
- **README.md** - This file

## Next Steps After Bootstrap

1. **Review Generated Files:**
   - `AGENTS.md` - AI agent guidelines
   - `.tech-decisions.yml` - Technology choices
   - `docs/constraints.md` - Project rules

2. **Create Your First ADR:**
   - Copy `docs/adr/ADR_TEMPLATE.md`
   - Create `docs/adr/ADR-0001-[decision].md`
   - Document a key architectural decision

3. **Customize Task Tracking:**
   - Edit `.llm/tasks.md` with your project tasks
   - Update task format with project-specific sections

4. **Test the Setup:**
   - Make a small change
   - Commit with conventional commit format
   - Verify hooks run successfully

5. **Re-run After Updating:**
   - Run `./bootstrap-ai-repo.ps1 -Force` to re-apply after upgrading the framework

## Task Format Reference

### Markdown Format (.llm/tasks.md)

```markdown
# Implementation Tasks

## Project Context
- [Key architectural detail]: [Description]

## Shared Types Registry
- [Type name]: [Usage/purpose]

## Rules & Tips
- [Discovered pattern]: [Details]

## Task List

- [ ] 1.0 Parent Task
  - Context:
    - [Background/why this matters]
    - [File locations]
    - [Dependencies]
  - Assertions: [Testing requirements]
  - [ ] 1.1 Subtask
  - [ ] 1.2 Subtask
```

## Troubleshooting

### Tasks Not Being Found

1. Check `.llm/tasks.md` exists: `ls .llm/tasks.md`
2. Verify format is correct (checklist items with `- [ ]`)

### Git Hooks Not Running

```bash
# Ensure .git/hooks is configured
git config core.hooksPath .githooks

# Make scripts executable
chmod +x .githooks/pre-commit
chmod +x .githooks/commit-msg
chmod +x .githooks/pre-push

# Test hook
./.githooks/pre-commit
```

## Integration with the Agent Pipeline

The bootstrap enables the agent pipeline to:

1. **Planner agent**: Create `.llm/tasks.md`
2. **Coder agent**: Read and execute the next task
3. **Infrastructure Engineer agent**: Execute infrastructure tasks
4. **Verifier agent**: Check tasks against the implementation

See [claude-agents/README.md](../../claude-agents/README.md) for the full agent roster and
pipeline graph.
