#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bootstrap AI-assisted development framework for a repository
.DESCRIPTION
    Sets up AI memory structure, commit hooks, CI configuration, and tech stack detection
.PARAMETER Force
    Overwrite existing files
.EXAMPLE
    .\bootstrap-ai-repo.ps1
    .\bootstrap-ai-repo.ps1 -Force
#>

param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root = Split-Path -Parent $scriptDir

# Color output helpers
function Write-Step
{
    param([string]$Message)
    Write-Host "`n$Message" -ForegroundColor Yellow
}

function Write-Success
{
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info
{
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Cyan
}

function Write-Warning
{
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Error
{
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  AI-Assisted Development Framework Bootstrap              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Verify we're in a git repository
if (-not (Test-Path "$root/.git"))
{
    Write-Error "Not in a git repository. Initialize git first: git init"
    exit 1
}

# ============================================================================
# Step 1: Create AI Memory Structure
# ============================================================================
Write-Step "[1/5] Creating AI memory structure..."

$memoryScript = Join-Path $scriptDir "create-llm-memory.ps1"
if (Test-Path $memoryScript)
{
    $args = @()
    if ($Force)
    {
        $args += "-Force" 
    }
    & $memoryScript @args
    Write-Success "AI memory structure created"
}
else
{
    Write-Warning "create-llm-memory.ps1 not found, creating minimal structure..."

    # Create minimal structure
    $dirs = @(
        "$root/docs",
        "$root/docs/adr",
        "$root/docs/standards",
        "$root/.githooks"
    )

    foreach ($dir in $dirs)
    {
        if (-not (Test-Path $dir))
        {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    Write-Success "Minimal directory structure created"
}

# ============================================================================
# Step 2: Create Git Hooks
# ============================================================================
Write-Step "[2/5] Creating git hooks..."

$hooksDir = Join-Path $root ".githooks"

# Ensure .githooks exists
if (-not (Test-Path $hooksDir))
{
    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
}

# Create pre-commit hook
$preCommit = @'
#!/bin/bash
# Pre-commit hook for AI-assisted development
# Fast checks that run before each commit

set -e

echo "🔍 Running pre-commit checks..."

# Track if any checks fail
FAILED=0

# ============================================================================
# 1. Secrets Detection
# ============================================================================
echo "  • Checking for secrets..."
if command -v detect-secrets >/dev/null 2>&1; then
    if [ -f ".secrets.baseline" ]; then
        if ! detect-secrets scan --baseline .secrets.baseline 2>/dev/null; then
            echo "    ✗ Potential secrets detected!"
            echo "      Review findings and update .secrets.baseline if needed"
            FAILED=1
        fi
    else
        echo "    ⚠ No .secrets.baseline found. Run: detect-secrets scan --baseline .secrets.baseline"
    fi
else
    echo "    ⚠ detect-secrets not installed (optional but recommended)"
fi

# ============================================================================
# 2. Large Files
# ============================================================================
echo "  • Checking for large files..."
large_files=$(git diff --cached --name-only --diff-filter=d | while read file; do
    if [ -f "$file" ]; then
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        if [ "$size" -gt 5242880 ]; then  # 5MB
            echo "$file ($((size / 1048576))MB)"
        fi
    fi
done)

if [ -n "$large_files" ]; then
    echo "    ✗ Large files detected (>5MB):"
    echo "$large_files" | sed 's/^/      /'
    echo "      Consider using Git LFS or excluding from repo"
    FAILED=1
fi

# ============================================================================
# 3. Merge Conflict Markers
# ============================================================================
echo "  • Checking for merge conflict markers..."
if git diff --cached | grep -E '^(<<<<<<<|=======|>>>>>>>)' >/dev/null; then
    echo "    ✗ Merge conflict markers found"
    FAILED=1
fi

# ============================================================================
# 4. Language-Specific Checks
# ============================================================================

# Rust
if [ -f "Cargo.toml" ]; then
    echo "  • Rust: Checking format..."
    if ! cargo fmt -- --check 2>/dev/null; then
        echo "    ✗ Code not formatted. Run: cargo fmt"
        FAILED=1
    fi

    echo "  • Rust: Running clippy (fast checks)..."
    if ! cargo clippy --all-targets -- -D warnings -W clippy::all 2>/dev/null; then
        echo "    ✗ Clippy warnings found"
        FAILED=1
    fi
fi

# JavaScript/TypeScript
if [ -f "package.json" ]; then
    echo "  • JS/TS: Checking format..."
    if command -v npx >/dev/null 2>&1; then
        if ! npx prettier --check . 2>/dev/null; then
            echo "    ✗ Code not formatted. Run: npx prettier --write ."
            FAILED=1
        fi

        echo "  • JS/TS: Running linter..."
        if ! npx eslint . 2>/dev/null; then
            echo "    ✗ ESLint warnings found"
            FAILED=1
        fi
    fi
fi

# Python
if [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
    echo "  • Python: Checking format..."
    if command -v black >/dev/null 2>&1; then
        if ! black --check . 2>/dev/null; then
            echo "    ✗ Code not formatted. Run: black ."
            FAILED=1
        fi
    fi

    if command -v ruff >/dev/null 2>&1; then
        echo "  • Python: Running ruff..."
        if ! ruff check . 2>/dev/null; then
            echo "    ✗ Ruff checks failed"
            FAILED=1
        fi
    fi
fi

# .NET
if [ -f "*.csproj" ] || [ -f "*.sln" ]; then
    echo "  • .NET: Checking format..."
    if command -v dotnet >/dev/null 2>&1; then
        if ! dotnet format --verify-no-changes 2>/dev/null; then
            echo "    ✗ Code not formatted. Run: dotnet format"
            FAILED=1
        fi
    fi
fi

# ============================================================================
# Result
# ============================================================================
if [ $FAILED -eq 1 ]; then
    echo ""
    echo "❌ Pre-commit checks failed"
    echo "   Fix the issues above or use --no-verify to bypass (not recommended)"
    echo "   CI will re-run these checks and enforce them."
    exit 1
else
    echo ""
    echo "✅ Pre-commit checks passed"
    exit 0
fi
'@

$preCommitPath = Join-Path $hooksDir "pre-commit"
$preCommit | Out-File -FilePath $preCommitPath -Encoding UTF8 -NoNewline
Write-Success "Created pre-commit hook"

# Create commit-msg hook
$commitMsg = @'
#!/bin/bash
# Commit message validation hook
# Ensures commits include sufficient context

commit_msg_file=$1
commit_msg=$(cat "$commit_msg_file")

# Skip merge commits
if echo "$commit_msg" | grep -q "^Merge"; then
    exit 0
fi

# Skip revert commits
if echo "$commit_msg" | grep -q "^Revert"; then
    exit 0
fi

echo "🔍 Validating commit message..."

FAILED=0

# ============================================================================
# 1. Minimum length check
# ============================================================================
msg_length=${#commit_msg}
if [ $msg_length -lt 15 ]; then
    echo "  ✗ Commit message too short ($msg_length chars, need 15+)"
    echo "    Provide context: what changed and why"
    FAILED=1
fi

# ============================================================================
# 2. Check for lazy/vague messages
# ============================================================================
first_line=$(echo "$commit_msg" | head -n1)
if echo "$first_line" | grep -qiE '^(fix|update|change|wip|refactor|stuff|things|misc)$'; then
    echo "  ✗ Commit message too vague: '$first_line'"
    echo "    Be specific: 'fix login validation' not just 'fix'"
    FAILED=1
fi

# ============================================================================
# 3. Check for required ADR references (infrastructure/schema changes)
# ============================================================================
changed_files=$(git diff --cached --name-only)

# Check if infrastructure/schema files changed
if echo "$changed_files" | grep -qE '(migration|schema|terraform|\.sql$|infrastructure/)'; then
    if ! echo "$commit_msg" | grep -qiE '(ADR-[0-9]+|adr[- ]|decision record|see docs/)'; then
        echo "  ⚠ Infrastructure/schema change detected"
        echo "    Consider referencing relevant ADR: 'See ADR-XXXX' or 'See docs/adr/...'"
        # Warning only, don't fail
    fi
fi

# ============================================================================
# 4. Suggest adding 'why' for single-line commits
# ============================================================================
line_count=$(echo "$commit_msg" | wc -l | tr -d ' ')
if [ "$line_count" -eq 1 ] && [ $msg_length -lt 60 ]; then
    echo "  ℹ Single-line commit. Consider adding:"
    echo "    - Why this change is needed"
    echo "    - What alternatives were considered"
    echo "    Example:"
    echo "      Fix login validation"
    echo ""
    echo "      The previous regex allowed invalid emails. Switched to"
    echo "      email-validator library for RFC compliance."
fi

# ============================================================================
# Result
# ============================================================================
if [ $FAILED -eq 1 ]; then
    echo ""
    echo "❌ Commit message validation failed"
    echo "   Update your message or use --no-verify to bypass (not recommended)"
    exit 1
else
    echo "✅ Commit message validated"
    exit 0
fi
'@

$commitMsgPath = Join-Path $hooksDir "commit-msg"
$commitMsg | Out-File -FilePath $commitMsgPath -Encoding UTF8 -NoNewline
Write-Success "Created commit-msg hook"

# Make hooks executable (cross-platform)
if (Get-Command "chmod" -ErrorAction SilentlyContinue)
{
    chmod +x $preCommitPath
    chmod +x $commitMsgPath
    Write-Info "Made hooks executable"
}

# Configure git to use .githooks
try
{
    git config core.hooksPath .githooks
    Write-Success "Git configured to use .githooks/"
}
catch
{
    Write-Error "Failed to configure git hooks: $_"
    exit 1
}

# ============================================================================
# Step 3: Detect Tech Stack
# ============================================================================
Write-Step "[3/5] Detecting tech stack..."

$languages = @()
$frameworks = @()

# Detect Rust
if (Test-Path "$root/Cargo.toml")
{
    $languages += "rust"
    Write-Info "Detected: Rust"
}

# Detect JavaScript/TypeScript
if (Test-Path "$root/package.json")
{
    $languages += "javascript"
    Write-Info "Detected: JavaScript"

    if ((Test-Path "$root/tsconfig.json") -or (Test-Path "$root/package.json"))
    {
        $packageContent = Get-Content "$root/package.json" -Raw | ConvertFrom-Json
        if ($packageContent.devDependencies -and $packageContent.devDependencies.typescript)
        {
            $languages += "typescript"
            Write-Info "Detected: TypeScript"
        }
    }
}

# Detect Python
if ((Test-Path "$root/setup.py") -or (Test-Path "$root/pyproject.toml") -or (Test-Path "$root/requirements.txt"))
{
    $languages += "python"
    Write-Info "Detected: Python"
}

# Detect .NET
$csprojFiles = Get-ChildItem -Path $root -Filter "*.csproj" -ErrorAction SilentlyContinue
if ($csprojFiles -or (Test-Path "$root/*.sln"))
{
    $languages += "csharp"
    Write-Info "Detected: C#/.NET"
}

# Detect Go
if (Test-Path "$root/go.mod")
{
    $languages += "go"
    Write-Info "Detected: Go"
}

Write-Success "Tech stack detection complete"

# ============================================================================
# Step 4: Create .tech-decisions.yml
# ============================================================================
Write-Step "[4/5] Creating .tech-decisions.yml..."

$techDecisions = @"
# Technology Decisions and Standards
# Generated: $(Get-Date -Format "yyyy-MM-dd")
# This file is read by CI and commit hooks to enforce standards

# Detected languages
languages: [$($languages -join ", ")]

# Database (customize for your project)
database:
  choice: null  # e.g., postgresql, mongodb, sqlite
  rationale: "See docs/adr/ADR-XXXX.md"
  alternatives_rejected: []
  forbidden_operations:
    - "Never use SELECT * in production code"
    - "Always use prepared statements"
    - "Never store passwords in plain text"

# HTTP client standards
http_client:
  $(if ($languages -contains "rust") { "rust: reqwest  # Standard HTTP client for Rust" })
  $(if ($languages -contains "python") { "python: httpx  # Async-first HTTP client" })
  $(if ($languages -contains "javascript") { "javascript: axios  # Standard for Node.js" })
  rationale: "Standardized for consistency across projects"

# Testing requirements
testing:
  unit_coverage_minimum: 80
  mutation_score_minimum: 70
  integration_test_required_for:
    - "API endpoints"
    - "Database migrations"
    - "External service integrations"
    - "Authentication/authorization logic"

  # Test naming conventions
  test_naming: "test_<function>_<scenario>_<expected>"

  # Required test types
  required_test_types:
    - "unit"        # Fast, isolated tests
    - "integration" # Tests with real dependencies
    - "e2e"         # Full user journey tests (for user-facing apps)

# Code quality standards
code_quality:
  max_function_length: 50
  max_file_length: 500
  max_complexity: 10
  no_duplicate_blocks: true

  # Naming conventions
  naming:
    variables: "snake_case"
    functions: "snake_case"
    classes: "PascalCase"
    constants: "SCREAMING_SNAKE_CASE"

# Security standards
security:
  secret_management: "environment variables or secret manager"
  no_hardcoded_secrets: true
  required_security_headers:
    - "Content-Security-Policy"
    - "X-Frame-Options"
    - "X-Content-Type-Options"

  dependency_scanning:
    enabled: true
    fail_on: "high"  # Severity level: low, medium, high, critical

# Infrastructure standards (customize as needed)
infrastructure:
  deployment: null  # e.g., kubernetes, lambda, vm, container

  always:
    - "Include health check endpoint"
    - "Add readiness and liveness probes"
    - "Set resource limits"
    - "Use semantic versioning for releases"
    - "Tag container images with commit SHA"

  never:
    - "Hard-code credentials"
    - "Use 'latest' tag in production"
    - "Deploy without smoke tests"
    - "Skip database backups"

# Documentation requirements
documentation:
  required_for:
    - "Public APIs"
    - "Database schema changes"
    - "Security-related changes"
    - "Performance-critical code"

  adr_required_for:
    - "Architectural decisions"
    - "Technology choices"
    - "Security model changes"
    - "Data model changes"

# Performance standards
performance:
  max_response_time_p95: "200ms"  # API endpoints
  max_db_query_time: "100ms"
  bundle_size_limit: "500kb"  # For web frontends
"@

$techDecisionsPath = Join-Path $root ".tech-decisions.yml"
if ((Test-Path $techDecisionsPath) -and -not $Force)
{
    Write-Warning ".tech-decisions.yml already exists (use -Force to overwrite)"
}
else
{
    $techDecisions | Out-File -FilePath $techDecisionsPath -Encoding UTF8
    Write-Success "Created .tech-decisions.yml"
}

# ============================================================================
# Step 5: Setup Beads (Optional Task Tracking)
# ============================================================================
Write-Step "[5/6] Setting up Beads task tracking (optional)..."

$beadsInstalled = $false
try
{
    $null = Get-Command "bd" -ErrorAction Stop
    $beadsInstalled = $true
    Write-Info "Beads already installed"
}
catch
{
    $beadsInstalled = $false
}

if ($beadsInstalled)
{
    # Initialize Beads in the repo
    try
    {
        Push-Location $root
        bd init 2>&1 | Out-Null
        Write-Success "Initialized Beads task tracking"

        # Update AGENTS.md with task tracking section
        $agentsFile = Join-Path $root "AGENTS.md"
        if (Test-Path $agentsFile)
        {
            $beadsSection = @"


## Task Management

This project uses Beads (bd) for AI-friendly task tracking.

### Before starting work

1. Check what's ready: ``bd ready --json``
2. Pick a task: ``bd show bd-abc --json``
3. Start work: ``bd update bd-abc working``

### When creating new tasks

1. Create issue: ``bd create "Task description" -p 1 -t feature``
2. Add dependencies: ``bd update bd-xyz --blocks bd-abc``
3. The task will auto-appear in ``bd ready`` when blockers are done

### When finishing work

1. Commit with issue ID: ``git commit -m "Fix auth bug (bd-abc)"``
2. Close issue: ``bd close bd-abc --reason "Completed"``
3. Sync: ``bd sync`` (usually automatic)

### Integration with ADRs

- Link ADRs in task descriptions: "See ADR-0005 for context"
- Create tasks for implementing ADR decisions
- Reference task IDs in ADR implementation notes

### Quick reference

````bash
bd ready              # Show tasks ready to work on
bd create "desc" -p 1 # Create new task (priority 1-5)
bd show bd-xyz        # Show task details
bd update bd-xyz working  # Mark task in progress
bd close bd-xyz       # Close completed task
bd search "keyword"   # Search tasks
bd doctor             # Check for orphaned work
````
"@
            Add-Content -Path $agentsFile -Value $beadsSection
            Write-Success "Updated AGENTS.md with task tracking guidance"
        }

        # Update .tech-decisions.yml with task tracking config
        $techFile = Join-Path $root ".tech-decisions.yml"
        if (Test-Path $techFile)
        {
            $taskTrackingConfig = @"

# Task tracking configuration
task_tracking:
  tool: beads
  required_in_commit: recommended  # Recommend bd-xxx in commit messages
  auto_close_on_merge: false  # Manual close for explicit decision tracking

  # When to create tasks
  task_required_for:
    - "New features"
    - "Bug fixes"
    - "Architectural changes"
    - "Infrastructure changes"

  # Task types (align with your workflow)
  types:
    - feature      # New functionality
    - bug          # Bug fixes
    - refactor     # Code improvements
    - docs         # Documentation
    - infrastructure  # Build, deploy, tooling
    - security     # Security fixes/improvements
"@
            Add-Content -Path $techFile -Value $taskTrackingConfig
            Write-Success "Updated .tech-decisions.yml with task tracking config"
        }

        # Create initial setup tasks
        Write-Info "Creating initial framework setup tasks..."
        bd create "Customize docs/constraints.md with project-specific rules" -p 1 -t docs 2>&1 | Out-Null
        bd create "Fill in .tech-decisions.yml with actual tech choices" -p 1 -t docs 2>&1 | Out-Null
        bd create "Create first ADR documenting initial architectural decision" -p 2 -t docs 2>&1 | Out-Null
        bd create "Review and customize pre-commit hooks for project needs" -p 3 -t infrastructure 2>&1 | Out-Null

        Write-Info "Created 4 initial setup tasks. Run 'bd ready' to see them."

    }
    catch
    {
        Write-Warning "Failed to initialize Beads: $_"
    }
    finally
    {
        Pop-Location
    }
}
else
{
    Write-Warning "Beads not installed. Task tracking is optional but recommended."
    Write-Info ""
    Write-Info "To install Beads and enable task tracking:"
    Write-Info "  Windows (WSL or Git Bash):"
    Write-Info "    curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash"
    Write-Info "  Then run: bd init"
    Write-Info ""
    Write-Info "Benefits of Beads:"
    Write-Info "  • AI-friendly task tracking with JSON output"
    Write-Info "  • Dependency management (what's blocking what)"
    Write-Info "  • Git-versioned (no external services needed)"
    Write-Info "  • Multi-agent coordination safe"
    Write-Info ""
    Write-Info "In the meantime, AI modes will use ./.llm/tasks.md for task tracking."
}

# ============================================================================
# Step 5b: Initialize Fallback Task Structure
# ============================================================================
Write-Step "[5b/6] Initializing fallback task structure (.llm/tasks.md)..."

$llmDir = Join-Path $root ".llm"
if (-not (Test-Path $llmDir))
{
    New-Item -ItemType Directory -Path $llmDir -Force | Out-Null
    Write-Success "Created .llm directory"
}

# Create a template tasks.md if it doesn't exist
$tasksFile = Join-Path $llmDir "tasks.md"
if (-not (Test-Path $tasksFile))
{
    $tasksTemplate = @"
# Implementation Tasks

> **Note**: This file serves as the fallback task source when Beads is not available.
> If Beads is installed and initialized, tasks can be synced using: `scripts/tasks-export.ps1` or `scripts/tasks-export.sh`

## Project Context

- Framework: AI-assisted development with Beads task tracking
- Task Format: Standard Markdown checklist
- Integration: Modes auto-detect Beads; fall back to this file when unavailable

## Shared Types Registry

> Populated during implementation as reusable types are discovered

## Rules & Tips

> Populated during implementation as project patterns emerge

## Task List

- [ ] 1.0 Initialize Project
  - Context:
    - This is a placeholder task for project setup
    - Customize this template with your actual implementation tasks
  - Assertions: none
  - [ ] 1.1 Review and customize .tech-decisions.yml
  - [ ] 1.2 Set up initial ADRs (Architecture Decision Records)
"@
    $tasksTemplate | Out-File -FilePath $tasksFile -Encoding UTF8
    Write-Success "Created .llm/tasks.md template"
}
else
{
    Write-Info ".llm/tasks.md already exists (skipped)"
}

# ============================================================================
# Step 6: Create CI Configuration
# ============================================================================
Write-Step "[6/6] Creating CI configuration..."

$githubDir = Join-Path $root ".github/workflows"
if (-not (Test-Path $githubDir))
{
    New-Item -ItemType Directory -Path $githubDir -Force | Out-Null
}

# Create quality.yml
$qualityYml = @"
name: Quality Checks

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  fast-checks:
    name: Fast Quality Checks
    runs-on: ubuntu-latest
    timeout-minutes: 10

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      # Task tracking validation (if Beads is used)
      - name: Check task tracking
        continue-on-error: true
        run: |
          if command -v bd >/dev/null 2>&1; then
            # Check if commit has task ID
            if ! git log --format=%s -1 | grep -E '\(bd-[a-z0-9]+\)'; then
              echo "::warning::No task ID in commit message. Consider: (bd-xxx)"
            fi

            # Check for orphaned work (commits without closed tasks)
            if bd doctor --orphans --json 2>/dev/null | grep -q "orphans"; then
              echo "::warning::Found commits with task IDs but tasks not closed"
              bd doctor --orphans
            fi
          fi

      # Re-run all pre-commit checks (in case bypassed locally)
      - name: Check for secrets
        run: |
          pip install detect-secrets
          if [ -f ".secrets.baseline" ]; then
            detect-secrets scan --baseline .secrets.baseline
          else
            echo "No .secrets.baseline found, creating one..."
            detect-secrets scan --baseline .secrets.baseline
          fi

      # Language-specific checks
$(if ($languages -contains "rust") {@"

      - name: Rust - Setup
        uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
          components: rustfmt, clippy

      - name: Rust - Format check
        run: cargo fmt -- --check

      - name: Rust - Clippy
        run: cargo clippy --all-targets -- -D warnings

      - name: Rust - Build
        run: cargo build --all-targets

      - name: Rust - Unit tests
        run: cargo test --lib
"@})
$(if ($languages -contains "javascript" -or $languages -contains "typescript") {@"

      - name: Node - Setup
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          cache: 'npm'

      - name: Node - Install dependencies
        run: npm ci

      - name: Node - Format check
        run: npx prettier --check .

      - name: Node - Lint
        run: npx eslint .

      - name: Node - Type check
        if: hashFiles('tsconfig.json') != ''
        run: npx tsc --noEmit

      - name: Node - Unit tests
        run: npm test -- --coverage=false
"@})
$(if ($languages -contains "python") {@"

      - name: Python - Setup
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Python - Install dependencies
        run: |
          pip install black ruff mypy pytest
          if [ -f requirements.txt ]; then pip install -r requirements.txt; fi

      - name: Python - Format check
        run: black --check .

      - name: Python - Lint
        run: ruff check .

      - name: Python - Type check
        run: mypy src/ || true

      - name: Python - Unit tests
        run: pytest tests/
"@})

  comprehensive-checks:
    name: Comprehensive Validation
    runs-on: ubuntu-latest
    timeout-minutes: 30
    needs: fast-checks

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

$(if ($languages -contains "rust") {@"
      - name: Rust - Setup
        uses: actions-rs/toolchain@v1
        with:
          toolchain: stable

      - name: Rust - Full test suite with coverage
        run: |
          cargo install cargo-tarpaulin
          cargo tarpaulin --out Xml --all-features

      - name: Rust - Check coverage threshold
        run: |
          coverage=`$(xmllint --xpath "string(//coverage/@line-rate)" cobertura.xml)`
          if (( `$(echo "`$coverage < 0.80" | bc -l) )); then
            echo "Coverage `$coverage is below 80%"
            exit 1
          fi

      - name: Rust - Dependency audit
        run: |
          cargo install cargo-audit
          cargo audit
"@})

      - name: Upload coverage reports
        uses: codecov/codecov-action@v3
        with:
          fail_ci_if_error: true
"@

$qualityPath = Join-Path $githubDir "quality.yml"
if ((Test-Path $qualityPath) -and -not $Force)
{
    Write-Warning "quality.yml already exists (use -Force to overwrite)"
}
else
{
    $qualityYml | Out-File -FilePath $qualityPath -Encoding UTF8
    Write-Success "Created .github/workflows/quality.yml"
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  Bootstrap Complete!                                       ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Created:" -ForegroundColor Cyan
Write-Info "✓ AI memory structure (AGENTS.md, docs/)"
Write-Info "✓ Git hooks (.githooks/)"
Write-Info "✓ Tech decisions (.tech-decisions.yml)"
Write-Info "✓ CI configuration (.github/workflows/)"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Review and customize:" -ForegroundColor White
Write-Info "     • docs/constraints.md - Add project-specific rules"
Write-Info "     • .tech-decisions.yml - Fill in your tech choices"
Write-Info "     • AGENTS.md - Review AI guidelines"
Write-Host ""
Write-Host "  2. Create your first ADR:" -ForegroundColor White
Write-Info "     • Copy docs/adr/ADR_TEMPLATE.md"
Write-Info "     • Name it ADR-0001-your-decision.md"
Write-Info "     • Document a key architectural decision"
Write-Host ""
Write-Host "  3. Commit the framework:" -ForegroundColor White
Write-Info "     git add ."
Write-Info "     git commit -m 'Add AI-assisted development framework'"
Write-Host ""
Write-Host "  4. Test the hooks:" -ForegroundColor White
Write-Info "     Make a small change and commit to see hooks in action"
Write-Host ""
Write-Host "For help: See ai-assisted-development-framework.md" -ForegroundColor Cyan
Write-Host ""
