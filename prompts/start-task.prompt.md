---
mode: agent
description: Create a new branch and proceed with implementing the task based on the prepared implementation plan.
tools: ['search/codebase', 'edit/editFiles', 'runCommands', 'search', 'search/searchResults', 'runCommands/terminalLastCommand', 'runCommands/terminalSelection']
---

## 🎯 Task

You are an expert software engineer ready to implement a task. You have already analyzed the task using the read-task
prompt and prepared a detailed implementation plan. Now you will create a new branch and proceed with the
implementation following the plan.

## 🌿 Branch Creation

### Step 1: Determine Branch Name

Create a descriptive branch name following these conventions:

**Branch Naming Format:**
- `<type>/<work-item-number>-<short-description>` (if work item number available)
- `<type>/<short-description>` (if no work item number)

**Conventional Commit Types:**
- `feat/` - New features or functionality
- `fix/` - Bug fixes
- `refactor/` - Code restructuring without changing behavior
- `docs/` - Documentation changes
- `test/` - Adding or updating tests
- `chore/` - Maintenance tasks, dependencies, tooling
- `perf/` - Performance improvements
- `style/` - Code style/formatting changes

**Branch Naming Rules:**
- Use lowercase letters
- Use hyphens to separate words in the description
- Keep description concise but descriptive (3-6 words)
- Focus on the feature/change being made
- Do NOT include task numbers from `.llm/tasks.md`
- DO include work item numbers (e.g., issue #234, ticket ABC-456) if mentioned in the task

**Examples:**
- Task with work item #234 (feature): `feat/234-add-user-authentication`
- Task with ticket PROJ-567 (feature): `feat/proj-567-implement-api-caching`
- Task without work item (refactor): `refactor/database-queries`
- Task without work item (fix): `fix/error-logging-bug`
- Task without work item (docs): `docs/update-api-documentation`

### Step 2: Create the Branch

1. **Check current git status**:
   ```bash
   git status
   ```
   - Ensure working directory is clean
   - Note the current branch

2. **Create and switch to new branch**:
   ```bash
   git checkout -b <branch-name>
   ```

3. **Verify branch creation**:
   ```bash
   git branch --show-current
   ```

## 🚀 Implementation Process

### Step 1: Review Implementation Plan

Before starting, briefly review:
- The implementation plan from the read-task analysis
- The files to be created or modified
- Any specific requirements or constraints

### Step 2: Execute Implementation

Proceed with implementing the task according to:
- **Your current mode instructions** (coder, architect, etc.)
- The implementation plan prepared during task reading
- The project's coding standards and patterns

Your mode will guide the specific approach, including:
- How to structure the code
- Testing strategy and execution
- Commit patterns and frequency
- Validation steps

## ⚠️ Error Handling

If issues arise during implementation:

### Git Issues
- If branch already exists, inform the user and ask for guidance
- If working directory is not clean, show status and ask whether to stash or commit

## 🚨 Important Notes

- Always create a new branch with proper conventional commit type prefix
- Never work directly on main/master
- Follow the implementation plan and your mode's guidelines
