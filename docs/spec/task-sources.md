# Task Sources Contract

## Overview

This document defines the contract for task sources used by modes and prompts. Tasks are stored in `.llm/tasks.md` as a Markdown checklist and optionally exported to JSON by helper scripts for tool consumption.

## Task Source Types

### 1. Markdown Tasks (Source of Truth)

The Markdown task file is the primary source for all task tracking:

- **Location**: `./.llm/tasks.md`
- **Format**: Markdown checklist with optional metadata
- **Behavior**: Agents parse the first unchecked `- [ ]` task as the current task
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

### 2. JSON Export (Transient/Generated)

A temporary JSON file (`./.llm/tasks.json`) produced by helper scripts for tool consumption:

- **Location**: `./.llm/tasks.json` (project root)
- **Generation**: Created by `scripts/tasks-export.sh` (Linux/macOS) or `scripts/tasks-export.ps1` (Windows)
- **Source**: Converted from `./.llm/tasks.md` Markdown file
- **Schema**: See [JSON Task Format](#json-task-format) below
- **Lifespan**: Regenerated on-demand; not committed to version control

---

## Schemas

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

## Reading Tasks

Agents follow this process:

```
1. Check for ./.llm/tasks.md:
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

1. Read `./.llm/tasks.md`
2. Extract the current task and pass it to relevant prompts

### Prompts

Prompts (`prompts/*.prompt.md`):

- Accept task input from modes (already structured)
- Parse Markdown task format

### Bootstrap Scripts

Bootstrap scripts (in `tools/ai-bootstrap/` or similar):

- Create `.llm/tasks.md` on initialization if not present
- Document task format for end users

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
- [ ] Modes read `.llm/tasks.md` and find the current task
- [ ] No parse errors when reading `.llm/tasks.md`
