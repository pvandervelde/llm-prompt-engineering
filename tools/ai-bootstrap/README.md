# AI-Assisted Development Bootstrap

This directory contains scripts and documentation for setting up AI-assisted development in a repository.

## Quick Start

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

### 4. Task Tracking Setup (Optional)

- Creates `.llm/tasks.md` template
- AI modes auto-detect and parse this format
- Tasks are stored as Markdown checklist items

### 5. CI Configuration

- Generates `.github/workflows/` for language detection
- Creates fast-checks and comprehensive-checks pipelines
- Language-specific: Rust, JavaScript/TypeScript, Python
- Also creates `.github/workflows/pipeline-gates.yml` — seven required checks
  (`spec/assertion-coverage`, `spec/traceability`, `test/red-green-integrity`,
  `quality/mutation`, `quality/coverage-ratchet`, `security/findings`,
  `evidence/present`) that verify the agent pipeline's own gates against
  `.tech-decisions.yml` thresholds and `.llm/evidence/` artefacts, rather than
  trusting the pipeline's self-report. **This script does not configure branch
  protection** — after bootstrapping, a repo admin must add all seven jobs as
  required status checks on the default branch (Settings → Branches → Branch
  protection rules) for the gate to actually block merges.

## Task Tracking Details

### Task Tracking (.llm/tasks.md)

1. **Planner Mode** creates/updates `.llm/tasks.md`
2. **Coder Mode** reads and executes first unchecked task
3. **Helper Scripts** convert to JSON:
   - `scripts/tasks-export.ps1` / `scripts/tasks-export.sh` → JSON

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

AI modes follow this process:

1. **Check for `.llm/tasks.md`**
   - If exists → parse Markdown format
   - If not → ask user to create it

## Files in This Directory

- **bootstrap-ai-repo.ps1** - PowerShell bootstrap script (Windows)
- **bootstrap-ai-repo.sh** - Bash bootstrap script (Linux/macOS)
- **overview.md** - Comprehensive documentation of the framework
- **quick-reference.md** - Quick lookup for common tasks
- **ai-assisted-development-framework.md** - Detailed framework guide
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

5. **Enable Optional Features:**
   - Run `./bootstrap-ai-repo.ps1 -Force` to upgrade
   - Additional CI/CD integrations

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
3. Check modes have access to scripts/tasks-export.* helpers

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

## Integration with AI Modes

The bootstrap enables AI modes to:

1. **Planner Mode**: Create `.llm/tasks.md`
2. **Coder Mode**: Read and execute next task
3. **Infraengineer Mode**: Execute infrastructure tasks
4. **Read-Task Prompt**: Parse `.llm/tasks.md`
5. **Reviewer Mode**: Check tasks against implementation

## References

- Full framework documentation: [overview.md](./overview.md)
- Quick reference: [quick-reference.md](./quick-reference.md)
- Framework details: [ai-assisted-development-framework.md](./ai-assisted-development-framework.md)
- Task sources spec: [../../docs/spec/task-sources.md](../../docs/spec/task-sources.md)
