# Examples & Validation

This directory contains example task files and validation procedures for the Beads-compatible task handling system.

## Contents

### Example Files

- **example-tasks.md** - Complete example of Markdown task format (`.llm/tasks.md`)
- **example-tasks.json** - JSON format (Beads export or helper script output)
- **VALIDATION.md** - Comprehensive validation checklist

## Quick Start

### Using the Examples

1. **For a new project without Beads:**
   - Copy `example-tasks.md` to `.llm/tasks.md`
   - Customize with your project's tasks
   - AI modes will auto-detect and use it

2. **For a project with Beads:**
   - Use Beads to manage tasks: `bd create "Task description"`
   - Helper scripts will export to JSON format
   - AI modes will auto-detect Beads and use it

3. **Converting between formats:**

   ```bash
   # Markdown → JSON
   ./scripts/tasks-export.ps1  (Windows)
   ./scripts/tasks-export.sh   (Linux/Mac)

   # JSON → Beads
   ./scripts/tasks-import.ps1  (Windows)
   ./scripts/tasks-import.sh   (Linux/Mac)
   ```

### Understanding the Format

**Markdown Checklist Format:**

```markdown
- [ ] 1.0 Task Name
  - Context: Background, files, dependencies
  - Assertions: Testing requirements
  - [ ] 1.1 Subtask one
  - [ ] 1.2 Subtask two
```

**Key Principles:**

- Human-readable in version control
- Simple Markdown syntax (checklist items)
- Context blocks provide rich metadata
- Assertions define acceptance criteria
- Subtasks break work into atomic units

**JSON Export Format:**

```json
{
  "version": "1.0",
  "source": "markdown-export",
  "tasks": [
    {
      "id": "1.0",
      "title": "Task Name",
      "completed": false,
      "context": { /* details */ },
      "assertions": [ /* requirements */ ],
      "subtasks": [ /* array */ ]
    }
  ]
}
```

## Example Task Structure

The example files show a complete Node.js/TypeScript project with:

1. **Core Type System** - Foundation types used by all modules
2. **Authentication** - User auth with JWT tokens
3. **API Layer** - Express HTTP endpoints
4. **Database** - TypeORM persistence
5. **Documentation** - OpenAPI/Swagger
6. **CI/CD** - Automated testing and deployment

Each parent task includes:

- **Context:** Why it matters, which files, dependencies
- **Assertions:** Testing requirements from specs
- **Subtasks:** Atomic units of work (1-2 hours each)

## Validation

Before using tasks in your project:

```bash
# Check Markdown format
grep -E "^- \[[ x]\]" .llm/tasks.md  # Should see tasks

# Validate JSON format
jq empty < example-tasks.json        # Should succeed

# Test helper scripts
./scripts/tasks-export.ps1           # Should output JSON
./scripts/tasks-export.sh            # Should output JSON

# Verify mode integration
grep "tasks-export" modes/*.chatmode.md
grep "tasks-import" prompts/*.md
```

See [VALIDATION.md](./VALIDATION.md) for complete checklist.

## Customization

### Adapting the Example

1. **Project Context:** Update to match your tech stack
2. **Shared Types:** Add your domain types
3. **Rules & Tips:** Document your project's patterns
4. **Tasks:** Replace with your actual implementation tasks
5. **Subtasks:** Ensure they're atomic (< 2 hours each)

### Adding New Sections

The format is flexible. Consider adding:

```markdown
## API Endpoints
- POST /auth/login - Description

## Database Schema
- User table - Fields and indexes

## Performance Targets
- Response time < 100ms
- Throughput > 1000 req/s
```

## AI Mode Integration

AI modes automatically:

1. **Detect Beads:** `beads --version`
2. **Decide format:**
   - If Beads available → use `scripts/tasks-export.ps1`
   - Otherwise → read `.llm/tasks.md`
3. **Find next task:** First `[ ]` (unchecked) item
4. **Parse content:** Extract context, assertions, subtasks
5. **Execute:** Start implementation

**No configuration needed** — modes just work with whatever format is available.

## References

- **Task Source Specification:** [docs/spec/task-sources.md](../docs/spec/task-sources.md)
- **Bootstrap Guide:** [tools/ai-bootstrap/README.md](../tools/ai-bootstrap/README.md)
- **Helper Scripts:** [scripts/tasks-export.ps1](../scripts/tasks-export.ps1), [scripts/tasks-export.sh](../scripts/tasks-export.sh)
- **Planner Mode:** [modes/planner.chatmode.md](../modes/planner.chatmode.md)
- **Coder Mode:** [modes/coder.chatmode.md](../modes/coder.chatmode.md)

## Getting Started

1. **New project:** Copy `example-tasks.md` to `.llm/tasks.md` and customize
2. **Existing project:** Run bootstrap: `./tools/ai-bootstrap/bootstrap-ai-repo.ps1`
3. **With Beads:** Install and run `bd init`, tasks auto-sync
4. **Validation:** Check [VALIDATION.md](./VALIDATION.md) checklist

---

**Questions?** See the full documentation in [tools/ai-bootstrap/](../tools/ai-bootstrap/) or [docs/spec/task-sources.md](../docs/spec/task-sources.md).
