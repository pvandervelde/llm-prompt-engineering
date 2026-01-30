# Task Sources Contract and Fallback Strategy

## Overview

This document defines the contract for task sources, enabling modes and prompts to optionally integrate with Beads (a task management tool) while gracefully falling back to a Markdown-based task file when Beads is unavailable.

## Task Source Types

### 1. Beads CLI (Primary)

When Beads is installed and available on the system PATH:

- **Detection**: Check for `beads --version` (exit code 0 indicates availability)
- **Export Command**: `beads export --format=json` (produces JSON task export)
- **Schema**: See [Beads JSON Export Schema](#beads-json-export-schema) below
- **Behavior**: Runtime agents detect Beads CLI and invoke the export command to retrieve current task state

### 2. JSON Export (Transient/Generated)

A temporary JSON file (`./.llm/tasks.json`) produced by helper scripts when Beads is unavailable:

- **Location**: `./.llm/tasks.json` (project root)
- **Generation**: Created by `scripts/tasks-export.sh` (Linux/macOS) or `scripts/tasks-export.ps1` (Windows)
- **Source**: Converted from `./.llm/tasks.md` Markdown file
- **Schema**: See [JSON Task Format](#json-task-format) below
- **Lifespan**: Regenerated on-demand; not committed to version control

### 3. Markdown Fallback (Human-Friendly Source of Truth)

The original Markdown task file used when both Beads and JSON export are unavailable:

- **Location**: `./.llm/tasks.md`
- **Format**: Markdown checklist with optional metadata
- **Behavior**: Agents parse first unchecked `- [ ]` task as the current task
- **Example**:

  ```markdown
  # Task List

  ## In Progress
  - [x] Task one completed
  - [ ] Task two (current task)
  - [ ] Task three

  ## Backlog
  - [ ] Task four
  ```

---

## Schemas

### Beads JSON Export Schema

```json
{
  "tasks": [
    {
      "id": "task-id-or-name",
      "title": "Task Title",
      "description": "Detailed description",
      "status": "open|in-progress|completed|blocked",
      "priority": "low|medium|high",
      "tags": ["tag1", "tag2"],
      "dueDate": "YYYY-MM-DD",
      "assignee": "user@example.com"
    }
  ]
}
```

**Current Task Logic**: Beads source should return tasks in priority/status order; agents consume the first task with status `open` or `in-progress`.

### JSON Task Format

Intermediate format for Markdown-to-JSON conversion:

```json
{
  "tasks": [
    {
      "id": "task-1",
      "title": "Task One",
      "description": "Description from markdown or empty",
      "status": "completed",
      "checked": true
    },
    {
      "id": "task-2",
      "title": "Task Two",
      "description": "",
      "status": "open",
      "checked": false
    }
  ]
}
```

**Markdown-to-JSON Rules**:

1. Parse lines matching `- [ ]` (unchecked) as status `open`
2. Parse lines matching `- [x]` (checked) as status `completed`
3. Extract task title from the text after the checkbox
4. Generate numeric IDs (task-1, task-2, …)
5. Description is empty unless preceded by indented notes

---

## Runtime Detection and Fallback Logic

Agents follow this decision tree:

```
1. Check for Beads CLI:
   - Run: beads --version
   - If exit code == 0 → Use Beads export (see Beads JSON Export Schema)
   - If command not found or non-zero exit → Continue to step 2

2. Check for ./.llm/tasks.json:
   - If file exists → Parse and consume (see JSON Task Format)
   - If file missing → Continue to step 3

3. Check for ./.llm/tasks.md:
   - If file exists → Parse Markdown and return first unchecked task
   - If file missing → Return "No task list available"
```

---

## Helper Scripts

### PowerShell: `scripts/tasks-export.ps1`

Exports tasks from `./.llm/tasks.md` to `./.llm/tasks.json` (Markdown-to-JSON conversion).

**Usage**:

```powershell
.\scripts\tasks-export.ps1
```

**Behavior**:

- Reads `./.llm/tasks.md` from the current directory
- Parses Markdown checklist format
- Writes JSON to `./.llm/tasks.json`
- Exits with code 0 on success, non-zero on error

### Bash: `scripts/tasks-export.sh`

Same functionality as PowerShell script, for Linux/macOS.

**Usage**:

```bash
bash scripts/tasks-export.sh
```

**Behavior**: (identical to PowerShell variant)

---

## Integration Points

### Modes

Modes (`modes/*.chatmode.md`) should:

1. Detect Beads availability at runtime
2. If available, invoke `beads export --format=json` and parse output
3. If unavailable, fall back to `./.llm/tasks.md` (via helper script if needed)
4. Extract current task and pass to relevant prompts

### Prompts

Prompts (`prompts/*.prompt.md`):

- Accept task input from modes (already structured)
- Preserve human-facing task reading requirement
- Parse JSON when provided by mode/helper; fall back to Markdown if necessary

### Bootstrap Scripts

Bootstrap scripts (in `tools/ai-bootstrap/` or similar):

- Detect Beads on initialization
- If missing, call `scripts/tasks-export.sh` or `.ps1` once
- Document fallback behavior for end users

---

## Example: Markdown Source

```markdown
# My Project Tasks

## Current Sprint
- [x] Design API endpoints
- [ ] Implement user authentication
- [ ] Add unit tests for auth module

## Backlog
- [ ] Build dashboard UI
- [ ] Setup CI/CD pipeline
```

**JSON Export Output**:

```json
{
  "tasks": [
    {
      "id": "task-1",
      "title": "Design API endpoints",
      "description": "",
      "status": "completed",
      "checked": true
    },
    {
      "id": "task-2",
      "title": "Implement user authentication",
      "description": "",
      "status": "open",
      "checked": false
    },
    {
      "id": "task-3",
      "title": "Add unit tests for auth module",
      "description": "",
      "status": "open",
      "checked": false
    },
    {
      "id": "task-4",
      "title": "Build dashboard UI",
      "description": "",
      "status": "open",
      "checked": false
    },
    {
      "id": "task-5",
      "title": "Setup CI/CD pipeline",
      "description": "",
      "status": "open",
      "checked": false
    }
  ]
}
```

---

## Validation Checklist

- [ ] `scripts/tasks-export.sh` runs successfully on Linux/macOS
- [ ] `scripts/tasks-export.ps1` runs successfully on Windows
- [ ] `./.llm/tasks.md` exists in project root
- [ ] `./.llm/tasks.json` is generated correctly from Markdown source
- [ ] Modes detect Beads and fall back gracefully
- [ ] Prompts parse both JSON and Markdown flows
- [ ] No parse errors when Beads is unavailable
