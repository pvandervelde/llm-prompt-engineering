<#
Creates the LLM memory folder structure and template files described in .llm/llm-memory-for-repos.md

Usage:
  .\create-llm-memory.ps1 [-Force]

Options:
  -Force  : Overwrite existing files if present
#>

param(
    [switch]$Force
)

Set-StrictMode -Version Latest

$root = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Ensure-Dir
{
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path))
    {
        New-Item -ItemType Directory -Path $Path | Out-Null
        Write-Host "Created directory: $Path"
    }
}

function Write-FileIfNeeded
{
    param([string]$Path, [string]$Content)
    if ((Test-Path -LiteralPath $Path) -and (-not $Force))
    {
        Write-Host "Skipping existing file: $Path (use -Force to overwrite)"
        return
    }
    $dir = Split-Path -Parent $Path
    Ensure-Dir -Path $dir
    $Content | Out-File -FilePath $Path -Encoding UTF8 -Force
    Write-Host "Wrote file: $Path"
}

# Directories to create
$dirs = @(
    "$root/docs",
    "$root/docs/adr",
    "$root/docs/standards",
)

foreach ($d in $dirs)
{
    Ensure-Dir -Path $d
}

# File contents (from provided templates)
$agents = @'
# Agent Instructions for Repository Context

## Before Making Changes

Agents working in this repository must consult the relevant memory documents before proposing changes.

### Items Changes
**Triggers:** Any file in `xxx/yyy/`, `xxx/yyy/`, or mentioning `aaa`, `bbb`, `ccc`

**Required reading:**
1. `docs/constraints.md` - Check constraints
2. Any ADRs tagged with `#aaa` or `#bbb`
3. `docs/standards/language.md` - standards

### Adding New Modules/Helpers
**Triggers:** Creating new files in `crates/`, `modules/`, `lib/`, `utils/`, `shared/`

**Required reading:**
1. `docs/catalog.md` - Check if something similar exists
2. `docs/standards/language.md` or relevant language standards

### XXXX Layer Changes
**Triggers:** Files in `xxx/yyy/`, `aa/`, or mentioning `aaa`, `bbbb`, `ccc`

**Required reading:**
1. `docs/constraints.md` - Check data layer constraints
2. ADRs tagged with `#aaa`

## General Rules

1. **Always check `docs/constraints.md` first** - It's the index of things we keep relearning
2. **Follow linked ADRs** - They contain the "why" and approved patterns
3. **Check the catalog** before creating new utilities/modules
4. **Reference ADRs in commit messages** when implementing a decision

## When These Docs Conflict

If an ADR contradicts a constraint or standard, the ADR wins (it's more recent). Flag the conflict for human review.
'@

$constraints = @'
# Repository Constraints - Things We Keep Relearning

**Purpose:** Quick reference for non-obvious constraints and decisions. Each item links to the full explanation (ADR/standard/catalog).

Last updated: 2026-01-16

---

## Code Standards

### TypeScript

- ✅ **Use existing retry utility** - Don't write your own. Use `src/shared/utils/async.retry()` → [Catalog](catalog.md#shared-utilities)

- ✅ **Custom error classes already exist** - Check `src/shared/errors/` before creating new ones → [Catalog](catalog.md#error-handling)

### Testing

- ⚠️ **Don't mock internal functions** - Only mock external dependencies (APIs, databases) → [TypeScript Standards](standards/typescript.md#testing)

---

## How to Use This File

1. **Before implementing** - Scan for relevant constraints
2. **When stuck** - Check if we've solved this before
3. **When onboarding** - Read all constraints to avoid common mistakes
4. **Keep updated** - Add new constraints as discovered (with ADR links)

## Adding New Constraints

When adding a constraint:
1. Keep it under 20 words
2. State the rule + the alternative
3. Link to the source of truth (ADR/standard/catalog)
4. Use ⚠️ for "do not do this" and ✅ for "do this"

---

## Decision

TBD

## Context

TBD

### What Doesn't Work

```code
func stuff() {
    // This approach fails because...
}
```

Error: `This code does not work`

## Approved Pattern

### Use this approach instead

```code
func do_other_stuff() {
    // This works because...
}
```

## Consequences

### Positive
- Clear, documented pattern that works
- Prevents hours of debugging

### Negative
- ??

### Mitigation
- ??

## Alternatives Considered

### Option 1: ??
- **Pro:** ?
- **Con:** ?
- **Decision:** ?

## References

- [Link to related ADR or doc](url)

## Review

**Next review:** 2025-01-15
'@

$catalog = @'
# Repository Catalog - What Already Exists

**Purpose:** Prevent reinventing wheels. Check here before creating new modules, helpers, or utilities.

Last updated: 2024-01-16

---

## Modules (`modules/`)

### `modules/a/`
**What:** Does A
**When to use:** Anytime you need A
**Key inputs:** `ab`, `ac`
**Key outputs:** `a`
**Docs:** `modules/a/README.md`

---

## Shared Utilities (`src/shared/utils/`)

### `async.ts`
**Functions:**
- `retry(fn, options)` - Retry with exponential backoff
- `timeout(promise, ms)` - Add timeout to any promise
- `parallel(tasks, concurrency)` - Run tasks with concurrency limit

**When to use:** Don't write your own retry/timeout logic

**Example:**
```typescript
import { retry } from '@/shared/utils/async';

const result = await retry(
  () => fetchFromAPI(id),
  { maxAttempts: 3, delayMs: 1000 }
);
```

### `validation.ts`
**Functions:**
- `isEmail(str)` - RFC 5322 email validation
- `isUUID(str)` - UUID v4 validation
- `sanitize(str)` - HTML/SQL injection prevention

**When to use:** Input validation in API handlers

---

## Error Handling (`src/shared/errors/`)

**Existing error classes:**
- `NotFoundError` - Resource not found (404)
- `ValidationError` - Input validation failed (400)
- `UnauthorizedError` - Authentication required (401)
- `ForbiddenError` - Insufficient permissions (403)
- `ConflictError` - Resource conflict (409)
- `InternalError` - Unexpected server error (500)

**When to use:** Don't create new error classes without checking here first

**Example:**
```typescript
import { NotFoundError } from '@/shared/errors';

if (!user) {
  throw new NotFoundError(`User ${id} not found`);
}
```

---

## How to Use This Catalog

**Before creating anything:**
1. Search this file for similar functionality
2. Check the linked README/docs for usage
3. If similar exists, use or extend it (don't duplicate)
4. If creating something new, add it here

**Keeping this updated:**
- When adding a module: Document it here
- When adding a utility: Document it here
- Review quarterly to remove deprecated items
'@

$standards_code = @'
# Code Standards

---

## File Organization

Put the file organization rules here.

---

## Naming Conventions

Put the naming conventions here.

---

'@

# Write files
Write-FileIfNeeded -Path (Join-Path $root "AGENTS.md") -Content $agents
Write-FileIfNeeded -Path (Join-Path $root "docs/constraints.md") -Content $constraints
# Note: ADR example files are intentionally not created by this script.
Write-FileIfNeeded -Path (Join-Path $root "docs/catalog.md") -Content $catalog
Write-FileIfNeeded -Path (Join-Path $root "docs/standards/code.md") -Content $standards_code

# ADR folder README and template (no example ADRs)
$adrReadme = @'
# ADRs (Architecture Decision Records)

This folder contains ADRs documenting important architectural decisions.

Naming: ADR-<number>-short-title.md

Do not add example ADRs automatically. Use the ADR template to create new ADRs.
'@

$adrTemplate = @'
# ADR Template

Title:
Status: Proposed / Accepted / Deprecated
Date: YYYY-MM-DD
Tags: #tag1 #tag2

## Context

Describe the problem and why it matters.

## Decision

What decision was made.

## Consequences

Positive/negative consequences and tradeoffs.
'@

Write-FileIfNeeded -Path (Join-Path $root "docs/adr/README.md") -Content $adrReadme
Write-FileIfNeeded -Path (Join-Path $root "docs/adr/ADR_TEMPLATE.md") -Content $adrTemplate

Write-Host "Done. Run '.\create-llm-memory.ps1 -Force' to overwrite existing files." -ForegroundColor Green
