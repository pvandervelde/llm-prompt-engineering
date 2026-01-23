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

This repository contains conventions, constraints, and decisions that are easy to miss.
Before proposing changes, pull the relevant repo memory docs into context.

## Always do this

1) Read `docs/constraints.md` (tripwires + hard rules)
2) Read `docs/catalog.md` (what already exists to reuse)
3) Read relevant standards in `docs/standards/` (language/domain specific)

## When to consult ADRs (mandatory triggers)

If your change touches any of the following, read the linked ADR(s) referenced from `docs/constraints.md`
and/or search `docs/adr/` by keyword:

### Architecture / boundaries

- cross-boundary integration (services, accounts, networks, tenants)
- auth, identity, permissions
- data storage, encryption, PII
- multi-region/multi-environment behavior
- performance or latency-sensitive paths

### Interfaces

- public API changes
- database schema changes
- message/event contracts
- CLI flags / config formats

### Risky domains

- networking, security, secrets, payments
- build/release pipelines
- migrations and backwards compatibility

## Contribution expectations

- Prefer small diffs
- Reuse existing helpers/modules before adding new ones
- If you introduce a new pattern or constraint, add an ADR and a `docs/constraints.md` entry
- When summarizing changes, link the ADR(s) / standards you relied on

## What to include in responses

When generating code or plans:

- cite which constraints apply
- name the standards followed (formatting, naming, error handling, etc.)
- mention existing modules/helpers used (from `docs/catalog.md`)
'@

$constraints = @'
# Repository constraints (read this first)

This file is the quick index of non-obvious rules and “things we keep relearning”.
Each item links to a source of truth (ADR, standards, or a guide).

Keep this file SHORT (10–30 items). Prefer links over long explanations.

## Hard constraints (must follow)

- **[Constraint title]**: One-line rule that is unambiguous.
  Do instead: one-line preferred approach.
  Source: `docs/adr/ADR-XXXX-...md`

  - **[Constraint title]**: One-line rule.
  Do instead: one-line approach.
  Source: `docs/standards/<topic>.md`

## Defaults (strong preferences)

- **Prefer [X] over [Y]** for [reason in 5–10 words].
  Source: `docs/adr/ADR-XXXX-...md`

## “Check before you build”

- **New shared helper/module?** Read: `docs/catalog.md`
- **Changing public API?** Read: `docs/standards/api.md` and relevant ADRs
- **Changing data model?** Read: `docs/standards/data.md` and relevant ADRs

## Keywords (for quick search)

Suggested keywords for searching ADRs:
`security`, `auth`, `api`, `data`, `migration`, `network`, `performance`, `build`, `release`, `observability`
'@

$catalog = @'
# Catalog (what exists / reuse map)

Purpose: prevent reinventing utilities, modules, patterns, and “hidden” features.

Add to this whenever a reusable component becomes “the standard way”.

## Common building blocks

- **`<path/to/component>`** — What it does (1 line)
  Use when: scenario (1 line)
  Key entry points: `foo()`, `bar()`, config keys, or main exports
  Notes: constraints or gotchas (optional, 1–2 lines)

- **`<path/to/component>`** — What it does
  Use when: ...
  Key entry points: ...

## Cross-cutting helpers

- Logging: `<path>` (how to use)
- Error handling: `<path>` (how to wrap/return errors)
- Configuration: `<path>` (how config is loaded/validated)
- Testing utilities: `<path>`

## Where to add new stuff

- “Reusable”: goes in `<shared path>`
- “Repo-specific”: goes in `<app path>`
- “Experimental”: goes in `<experimental path>` (and must not be depended on)

## Search keywords

`logging`, `config`, `http client`, `db`, `cache`, `retry`, `auth`, `metrics`, `tracing`, `cli`, `validation`
'@

$standards_readme = @'
# Standards

These are stable conventions that keep the repo consistent.

If a rule changes often, it probably belongs in an ADR or a short guide instead.

## Recommended standards files (create what applies)

- `coding.md` — naming, structure, error handling, testing expectations
- `api.md` — versioning, backwards compatibility, deprecation policy
- `data.md` — schema changes, migrations, privacy, retention
- `security.md` — secrets, auth, permissions, threat model basics
- `observability.md` — logs/metrics/tracing, required fields, sampling
- `build-release.md` — CI, artifact versioning, release process
- `style-<lang>.md` — language-specific conventions (go/rust/python/ts/etc.)
'@

$standards_code = @'
# Coding standards

## Structure

- Keep modules small and focused
- Prefer clear boundaries (domain vs infra vs adapters)
- Avoid circular dependencies

## Naming

- Use consistent naming for types, functions, and files
- Prefer explicit names over abbreviations

## Error handling

- Errors must include actionable context
- Don’t swallow errors; propagate or handle intentionally
- Prefer typed errors / error codes where supported

## Testing

- New logic requires tests
- Prefer unit tests for logic, integration tests for boundaries
- Tests must be deterministic (no real network/time without fakes)

## Backwards compatibility

- Public interfaces must be compatible or versioned
- Deprecations must include migration notes

## Security basics

- Never log secrets or tokens
- Use approved secret/config mechanisms
- Validate inputs at boundaries
'@

# Write files
Write-FileIfNeeded -Path (Join-Path $root "AGENTS.md") -Content $agents
Write-FileIfNeeded -Path (Join-Path $root "docs/constraints.md") -Content $constraints
# Note: ADR example files are intentionally not created by this script.
Write-FileIfNeeded -Path (Join-Path $root "docs/catalog.md") -Content $catalog
Write-FileIfNeeded -Path (Join-Path $root "docs/standards/README.md") -Content $standards_readme
Write-FileIfNeeded -Path (Join-Path $root "docs/standards/code.md") -Content $standards_code

# ADR folder README and template (no example ADRs)
$adrReadme = @'
# ADRs (Architecture Decision Records)

This folder contains ADRs documenting important architectural decisions.

Naming: ADR-<number>-short-title.md

Do not add example ADRs automatically. Use the ADR template to create new ADRs.
'@

$adrTemplate = @'
# ADR-XXXX: <Decision title>

Status: Proposed | Accepted | Deprecated | Superseded
Date: YYYY-MM-DD
Owners: <team or handle>

## Context

What problem are we solving? What constraints matter? What did we try?
Keep this short and concrete.

## Decision

One paragraph with the decision stated clearly and unambiguously.
Include “do / don’t” if needed.

## Consequences

- What this enables
- What this forbids
- What trade-offs we accept

## Alternatives considered

- Option A: why not
- Option B: why not

## Implementation notes

Practical guidance, sharp edges, rollout notes.

## Examples

Minimal code/config snippets that demonstrate the preferred approach.

## References

Links to docs, incidents, PRs, RFCs.
'@

Write-FileIfNeeded -Path (Join-Path $root "docs/adr/README.md") -Content $adrReadme
Write-FileIfNeeded -Path (Join-Path $root "docs/adr/ADR_TEMPLATE.md") -Content $adrTemplate

Write-Host "Done. Run '.\create-llm-memory.ps1 -Force' to overwrite existing files." -ForegroundColor Green
