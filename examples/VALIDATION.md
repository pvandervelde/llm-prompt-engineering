# Task Examples & Validation Checklist

This directory contains example task files and validation procedures for the task source.

## Files

- **example-tasks.md** - Complete example of `.llm/tasks.md` Markdown format
- **example-tasks.json** - JSON export format (helper scripts)
- **VALIDATION.md** - Validation checklist for task system

## Quick Overview

### Markdown Format (.llm/tasks.md)

Tasks are version-controlled in `.llm/tasks.md` using a simple Markdown checklist.

**Pros:**

- ✓ Easily version-controlled
- ✓ Human-readable in code review
- ✓ Simple Markdown syntax
- ✓ Works offline

### JSON Export Format (helper scripts)

A JSON representation generated from `.llm/tasks.md` by the helper scripts, useful when tools need structured data.

**Pros:**

- ✓ Structured data for parsing
- ✓ Supports complex metadata
- ✓ Tool-friendly

## Example Usage

### Creating Tasks

```bash
# Edit .llm/tasks.md manually
vim .llm/tasks.md

# Helper script converts to JSON if needed
./scripts/tasks-export.sh
```

### AI Modes Reading Tasks

All AI modes automatically:

1. Read `.llm/tasks.md`
2. Find first `- [ ]` task
3. Parse Markdown structure

### Exporting to JSON

**Markdown → JSON (for tooling):**

```bash
# Windows
.\scripts\tasks-export.ps1

# Linux/Mac
./scripts/tasks-export.sh
```

## Structure Conventions

### Markdown Format

```markdown
# Implementation Tasks

## Project Context
- Key: Value (architectural, testing, framework details)

## Shared Types Registry
- Type name: Description and file location

## Rules & Tips
- Pattern name: Description of convention

## Task List

- [ ] X.0 Parent Task Name
  - Context: Background, files, dependencies
  - Assertions: Test requirements
  - [ ] X.1 Subtask
  - [ ] X.2 Subtask
```

### JSON Export Format

```json
{
  "version": "1.0",
  "source": "markdown-export",
  "projectContext": { /* metadata */ },
  "sharedTypes": [ /* array */ ],
  "rules": [ /* array */ ],
  "tasks": [
    {
      "id": "1.0",
      "title": "Task Name",
      "completed": false,
      "priority": 1,
      "context": { /* details */ },
      "assertions": [ /* requirements */ ],
      "subtasks": [ /* array */ ]
    }
  ]
}
```

## Validation Checklist

Before committing or using tasks, verify:

### Markdown Format (.llm/tasks.md)

- [ ] File exists at `.llm/tasks.md`
- [ ] Starts with `# Implementation Tasks` heading
- [ ] Contains `## Project Context` section
- [ ] Contains `## Shared Types Registry` section
- [ ] Contains `## Rules & Tips` section
- [ ] Contains `## Task List` section
- [ ] All tasks use `- [ ]` or `- [x]` format
- [ ] All parent tasks have context block
- [ ] All parent tasks have assertions
- [ ] All subtasks use `- [ ]` format
- [ ] Markdown syntax is valid

**Test with:**

```bash
# Try to parse it
cat .llm/tasks.md | grep "^- \[\|^- \[x\]" | wc -l
# Should count tasks

# Validate syntax
pandoc .llm/tasks.md -t json > /dev/null
```

### JSON Export Format

- [ ] File is valid JSON (use `jq` to validate)
- [ ] Contains `version: "1.0"`
- [ ] Contains `source` field
- [ ] Contains `projectContext` object
- [ ] Contains `sharedTypes` array
- [ ] Contains `rules` array
- [ ] Contains `tasks` array
- [ ] Each task has: id, title, completed, priority
- [ ] Each task has: context, assertions
- [ ] Each task has: subtasks array
- [ ] All IDs are unique
- [ ] All boolean fields are actual booleans
- [ ] No trailing commas

**Test with:**

```bash
# Validate JSON syntax
jq empty < example-tasks.json
# Should exit with no output

# Count tasks
jq '.tasks | length' < example-tasks.json
# Should show count
```

### Scripts Functionality

- [ ] `scripts/tasks-export.ps1` runs without errors
- [ ] `scripts/tasks-export.sh` runs without errors
- [ ] Exported JSON is valid

**Test with:**

```bash
# Windows: Export to JSON
$output = .\scripts\tasks-export.ps1
if (-not $output) { throw "No output" }

# Linux: Export to JSON
output=$(./scripts/tasks-export.sh)
if [ -z "$output" ]; then echo "No output"; fi
```

### Mode Integration

- [ ] Planner mode can create/update `.llm/tasks.md`
- [ ] Coder mode can read first unchecked task
- [ ] Infraengineer mode can find next task
- [ ] read-task prompt parses `.llm/tasks.md`

**Test with:**

```bash
# Verify helpers exist
ls -la scripts/tasks-export.ps1
ls -la scripts/tasks-export.sh

# Verify modes reference them
grep -r "tasks-export" modes/
grep -r "tasks-export" prompts/
```

## Integration Verification

After setting up or modifying tasks, run this checklist:

### Pre-Commit

- [ ] `.llm/tasks.md` parses without errors
- [ ] First `[ ]` task is clearly marked
- [ ] Context blocks are complete
- [ ] No circular dependencies

### Pre-Push

- [ ] All test runners can find next task
- [ ] Syntax validation passes
- [ ] Helper scripts execute successfully

### Post-Merge

- [ ] CI passes
- [ ] All modes can parse and execute tasks
- [ ] No conflicts in `.llm/tasks.md`

## Example Commands

```bash
# Validate Markdown format
./scripts/validate-tasks-markdown.sh

# Validate JSON format
./scripts/validate-tasks-json.sh

# Test round-trip conversion
./scripts/test-tasks-conversion.sh

# List all tasks
./scripts/list-tasks.sh

# Show next task
./scripts/show-next-task.sh
```

## Troubleshooting

### Tasks not found

- Check `.llm/tasks.md` exists: `ls .llm/tasks.md`
- Check format is correct: `grep "^- \[\|^- \[x\]" .llm/tasks.md`
- Run export script: `./scripts/tasks-export.sh`

### Helper scripts not working

- Verify scripts are executable: `chmod +x scripts/tasks-*.ps1`
- Check script paths: `which pwsh`, `which bash`
- Run with verbose: `./scripts/tasks-export.sh -v`

### Mode can't read tasks

- Verify scripts/tasks-export.* exist and are executable
- Check `.llm/tasks.md` has valid Markdown
- Test helper scripts manually
- Review mode/prompt code for task-reading logic

## Further Reading

- [Task Sources Specification](../docs/spec/task-sources.md)
- [AI Bootstrap Guide](../tools/ai-bootstrap/README.md)
- [Quick Reference](../tools/ai-bootstrap/quick-reference.md)
