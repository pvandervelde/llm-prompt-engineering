# AI-Assisted Development Framework

A comprehensive system for maintaining quality, security, and consistency when using AI for development. This framework combines **AI-readable documentation** with **automated guardrails** to steer AI agents toward best practices while maintaining developer productivity.

## Table of Contents

1. [Quick Start](#quick-start)
2. [The Three Pillars](#the-three-pillars)
3. [Repository Structure](#repository-structure)
4. [Setup Instructions](#setup-instructions)
5. [Automated Checks](#automated-checks)
6. [AI Memory System](#ai-memory-system)
7. [Commit Hooks](#commit-hooks)
8. [CI Pipeline](#ci-pipeline)
9. [Language-Specific Configurations](#language-specific-configurations)
10. [Maintenance and Evolution](#maintenance-and-evolution)

---

## Quick Start

**For new repositories:**

```powershell
# Windows
.\scripts\bootstrap-ai-repo.ps1

# Linux/Mac
./scripts/bootstrap-ai-repo.sh
```

**For existing repositories:**

```powershell
# 1. Create AI memory structure
.\scripts\create-llm-memory.ps1

# 2. Setup commit hooks
.\scripts\setup-hooks.ps1

# 3. Configure CI (language-specific)
.\scripts\setup-ci.ps1
```

---

## The Three Pillars

### 1. AI Memory (Knowledge Layer)
**Purpose:** Give AI agents context about *what* to build and *how* to build it.

**Location:** `AGENTS.md`, `docs/constraints.md`, `docs/catalog.md`, `docs/standards/`, `docs/adr/`

**Content:** Architectural decisions, design patterns, reusable components, constraints

**Updated:** When making significant technical decisions

### 2. Commit Hooks (Fast Feedback Layer)
**Purpose:** Catch obvious mistakes *before* they enter version control.

**Location:** `.githooks/`

**Checks:** Formatting, linting, secrets, commit messages, quick validations

**Speed:** Must complete in seconds (< 10s ideal)

### 3. CI Pipeline (Authoritative Layer)
**Purpose:** Comprehensive validation that cannot be bypassed.

**Location:** `.github/workflows/` or `.gitlab-ci.yml`

**Checks:** Full tests, security scans, mutation testing, architecture compliance

**Speed:** Can be slower (< 15 min for critical path)

---

## Repository Structure

```
repo-root/
├── AGENTS.md                          # Entry point for AI agents
├── docs/
│   ├── constraints.md                 # Quick index of hard rules
│   ├── catalog.md                     # Reusable components
│   ├── adr/                           # Architecture Decision Records
│   │   ├── README.md
│   │   ├── ADR_TEMPLATE.md
│   │   ├── ADR-0001-use-rust.md
│   │   └── ADR-0002-postgres-choice.md
│   └── standards/
│       ├── README.md
│       ├── code.md                    # General coding standards
│       ├── api.md                     # API standards
│       ├── security.md                # Security requirements
│       └── rust.md / python.md / etc.
├── .githooks/                         # Version-controlled hooks
│   ├── pre-commit
│   ├── commit-msg
│   └── pre-push
├── scripts/
│   ├── create-llm-memory.ps1         # Bootstrap AI memory
│   ├── setup-hooks.ps1               # Install hooks (Windows)
│   ├── setup-hooks.sh                # Install hooks (Linux/Mac)
│   ├── setup-ci.ps1                  # Configure CI
│   └── validate-local.ps1            # Run all checks locally
├── .github/workflows/                # CI configuration
│   ├── quality.yml                   # Linting, formatting, tests
│   ├── security.yml                  # Security scans
│   └── integration.yml               # Integration/E2E tests
├── .pre-commit-config.yaml           # Optional: pre-commit framework
└── .tech-decisions.yml               # Machine-readable tech stack
```

---

## Setup Instructions

### Initial Bootstrap

Run the appropriate bootstrap script for your platform:

**Windows:**
```powershell
.\scripts\bootstrap-ai-repo.ps1
```

**Linux/Mac:**
```bash
./scripts/bootstrap-ai-repo.sh
```

This will:
1. Create the AI memory structure (`AGENTS.md`, `docs/`, etc.)
2. Install commit hooks
3. Detect languages and configure appropriate tooling
4. Create initial CI configuration
5. Generate `.tech-decisions.yml`

### Manual Setup

If you prefer step-by-step:

**1. Create AI Memory:**
```powershell
.\scripts\create-llm-memory.ps1
```

**2. Setup Hooks:**
```powershell
# Windows
.\scripts\setup-hooks.ps1

# Linux/Mac
./scripts/setup-hooks.sh
```

**3. Configure CI:**
Edit `.github/workflows/quality.yml` based on your tech stack

---

## Automated Checks

### Check Categories

| Category | Pre-Commit Hook | CI | Example Tools |
|----------|----------------|-----|---------------|
| **Formatting** | ✅ | ✅ | `cargo fmt`, `prettier`, `black` |
| **Linting** | ✅ (fast only) | ✅ (comprehensive) | `clippy`, `eslint`, `ruff` |
| **Secrets** | ✅ | ✅ | `detect-secrets`, `gitleaks` |
| **Unit Tests** | ❌ | ✅ | Language-specific test runners |
| **Coverage** | ❌ | ✅ | `cargo-tarpaulin`, `coverage.py` |
| **Mutation Testing** | ❌ | ✅ | `cargo-mutants`, `Stryker`, `mutmut` |
| **Integration Tests** | ❌ | ✅ | Custom test suites |
| **Duplication** | ⚠️ (optional) | ✅ | `jscpd`, `cargo-dupe` |
| **Security Scan** | ❌ | ✅ | `cargo audit`, `snyk`, CodeQL |
| **Architecture** | ❌ | ✅ | Custom validation scripts |

✅ = Always run  
❌ = Never run at this stage  
⚠️ = Optional/configurable

### Scaling Checks to Complexity

**Simple changes (1-2 files, < 100 lines):**
- Pre-commit: Format + lint
- CI: Fast tests only

**Medium changes (3-10 files, 100-500 lines):**
- Pre-commit: Format + lint + commit message validation
- CI: Full unit tests + integration tests

**Complex changes (10+ files, 500+ lines, or architectural):**
- Pre-commit: All checks + ensure ADR referenced
- CI: Full suite including mutation testing, security scans

---

## AI Memory System

### Core Files

#### `AGENTS.md`
The entry point for AI agents. Tells them:
- What to read before making changes
- When to consult ADRs
- Contribution expectations

**Template created by:** `create-llm-memory.ps1`

**Key sections:**
- Always do this (constraints, catalog, standards)
- Mandatory ADR triggers
- What to include in responses

#### `docs/constraints.md`
Quick index of non-negotiable rules and strong preferences.

**Format:**
```markdown
## Hard constraints (must follow)

- **Never use library X for Y**: Creates vendor lock-in and has security issues.
  Do instead: Use library Z (see ADR-0005).
  Source: `docs/adr/ADR-0005-library-choice.md`

## Defaults (strong preferences)

- **Prefer async over sync I/O** for better throughput.
  Source: `docs/standards/rust.md`

## "Check before you build"

- **New database schema?** Read: `docs/standards/data.md` and ADR-0002
```

**Keep this SHORT** (10-30 items). Link to details rather than explaining inline.

#### `docs/catalog.md`
Prevents reinventing utilities and helpers.

**Format:**
```markdown
## Common building blocks

- **`src/utils/retry.rs`** — Exponential backoff retry logic
  Use when: Making network requests that may fail transiently
  Key entry points: `RetryPolicy::default()`, `retry_with_policy()`
  Notes: Max 5 retries by default; configure via `RetryConfig`
```

**Update when:** A component becomes "the standard way" to do something.

#### `docs/adr/ADR-XXXX-title.md`
Architecture Decision Records document *why* decisions were made.

**Template structure:**
- Context (problem, constraints)
- Decision (clear statement)
- Consequences (enables/forbids/trade-offs)
- Alternatives considered
- Implementation notes
- Examples
- References

**Naming:** `ADR-0001-postgres-over-mongodb.md`

#### `docs/standards/*.md`
Stable conventions that don't change often.

**Common files:**
- `code.md` — Naming, structure, error handling
- `api.md` — Versioning, backwards compatibility
- `security.md` — Secrets, auth, permissions
- `rust.md` / `python.md` / etc. — Language-specific

### Machine-Readable Tech Stack

Create `.tech-decisions.yml` for automated validation:

```yaml
# Database
database:
  choice: postgresql
  rationale: "See ADR-0002"
  alternatives_rejected: [mongodb, mysql]
  forbidden_operations:
    - "Never use SELECT * in production code"
    - "Always use prepared statements"

# HTTP client
http_client:
  rust: reqwest
  python: httpx
  javascript: axios
  rationale: "Standardized across team for consistency"

# Infrastructure patterns
infrastructure:
  deployment: kubernetes
  always: 
    - "Include health check endpoint on /health"
    - "Add readiness probe on /ready"
    - "Set resource limits in manifests"
  never:
    - "Hard-code credentials"
    - "Use 'latest' tag in production"

# Testing
testing:
  unit_coverage_minimum: 80
  mutation_score_minimum: 70
  integration_test_required_for:
    - "API endpoints"
    - "Database migrations"
    - "External service integrations"

# Code quality
code_quality:
  max_function_length: 50
  max_file_length: 500
  max_complexity: 10
  no_duplicate_blocks: true
```

This file is:
- Read by CI to enforce rules
- Read by pre-commit hooks for quick validation
- Referenced by AI agents for decision-making

---

## Commit Hooks

### Philosophy

Hooks are **advisory guardrails**, not impenetrable walls:
- They can be bypassed with `--no-verify`
- CI is the authoritative enforcement layer
- Make them fast (< 10 seconds) and helpful

### Hook Placement

**Store hooks in version control:**

```
.githooks/
├── pre-commit       # Before commit is created
├── commit-msg       # Validates commit message
└── pre-push         # Before pushing (optional)
```

**Activate with:**
```bash
git config core.hooksPath .githooks
```

### Pre-Commit Hook

**Purpose:** Catch obvious mistakes before they enter history.

**Checks:**
1. **Secrets scanning** — Prevent committing credentials
2. **Formatting** — Auto-fix or require formatted code
3. **Quick linting** — Fast checks only (< 5s)
4. **Large file detection** — Block accidentally committed binaries
5. **Merge conflict markers** — Catch unresolved conflicts

**Example (cross-platform):**

```bash
#!/bin/bash
# .githooks/pre-commit

set -e

echo "Running pre-commit checks..."

# 1. Detect secrets
if command -v detect-secrets >/dev/null 2>&1; then
    detect-secrets scan --baseline .secrets.baseline
fi

# 2. Format check (language-specific)
if [ -f "Cargo.toml" ]; then
    echo "Checking Rust formatting..."
    cargo fmt -- --check
fi

if [ -f "package.json" ]; then
    echo "Checking JS/TS formatting..."
    npx prettier --check .
fi

# 3. Quick lint (fail fast)
if [ -f "Cargo.toml" ]; then
    echo "Running clippy (fast checks only)..."
    cargo clippy --all-targets -- -D warnings -W clippy::all
fi

# 4. Check for large files
large_files=$(git diff --cached --name-only --diff-filter=d | xargs -I{} find "{}" -type f -size +5M 2>/dev/null || true)
if [ -n "$large_files" ]; then
    echo "Error: Large files detected (>5MB):"
    echo "$large_files"
    echo "Use Git LFS or exclude from repo"
    exit 1
fi

# 5. Check for merge conflict markers
if git diff --cached | grep -E '^(<<<<<<<|=======|>>>>>>>)'; then
    echo "Error: Merge conflict markers found"
    exit 1
fi

echo "✓ Pre-commit checks passed"
```

### Commit-Msg Hook

**Purpose:** Ensure commits include context for future developers (and AIs).

**Checks:**
1. Minimum length (not just "fix")
2. Required sections (what/why/risk)
3. References to ADRs when needed

**Example:**

```bash
#!/bin/bash
# .githooks/commit-msg

commit_msg_file=$1
commit_msg=$(cat "$commit_msg_file")

# Skip merge commits
if echo "$commit_msg" | grep -q "^Merge"; then
    exit 0
fi

# Minimum length check
if [ ${#commit_msg} -lt 20 ]; then
    echo "Error: Commit message too short (< 20 chars)"
    echo "Provide context: what changed and why"
    exit 1
fi

# Check for required context in multi-line commits
line_count=$(echo "$commit_msg" | wc -l)
if [ "$line_count" -eq 1 ] && [ ${#commit_msg} -lt 50 ]; then
    echo "Warning: Single-line commit should be more descriptive"
    echo "Consider adding:"
    echo "  - Why this change is needed"
    echo "  - What alternatives were considered"
fi

# For infrastructure/schema changes, require ADR reference
if git diff --cached --name-only | grep -qE '(migrations/|terraform/|\.sql$)'; then
    if ! echo "$commit_msg" | grep -qiE '(ADR-[0-9]+|adr|decision record)'; then
        echo "Warning: Infrastructure change should reference relevant ADR"
        echo "Add 'See ADR-XXXX' if architectural decision applies"
    fi
fi

# Check for common lazy messages
if echo "$commit_msg" | grep -qiE '^(fix|update|change|wip|refactor)$'; then
    echo "Error: Commit message too vague"
    echo "Instead of '$commit_msg', describe what specifically changed"
    exit 1
fi

exit 0
```

### Pre-Push Hook (Optional)

**Purpose:** Run heavier checks before pushing to remote.

**Checks:**
1. Quick unit tests (< 30s)
2. Build verification
3. Integration tests (if fast enough)

**Example:**

```bash
#!/bin/bash
# .githooks/pre-push

echo "Running pre-push checks..."

# Run quick unit tests
if [ -f "Cargo.toml" ]; then
    cargo test --lib --quiet
fi

if [ -f "package.json" ]; then
    npm test -- --coverage=false --passWithNoTests
fi

echo "✓ Pre-push checks passed"
```

### Making Hooks Discoverable

**In `README.md`:**

```markdown
## First-Time Setup

### For Developers

```bash
# Clone repo
git clone <repo-url>
cd <repo>

# Run setup (installs hooks + tools)
./scripts/setup-hooks.sh  # Linux/Mac
.\scripts\setup-hooks.ps1  # Windows
```

### For AI Agents

Before making changes:
1. Read `AGENTS.md` for contribution guidelines
2. Run `./scripts/setup-hooks.sh` to enable local checks
3. Never bypass hooks with `--no-verify` unless documented exception
```

### Handling `--no-verify`

**Don't fight it** — make it visible:

1. **In CI**, check for evidence that hooks ran:
   ```yaml
   - name: Verify formatting was run
     run: |
       if ! cargo fmt -- --check; then
         echo "Code not formatted. Did you bypass pre-commit hooks?"
         exit 1
       fi
   ```

2. **Add gentle reminder** in hook failure messages:
   ```
   You can bypass with --no-verify, but CI will still enforce this check.
   ```

---

## CI Pipeline

### Pipeline Structure

**Three tiers of checks:**

#### Tier 1: Fast Feedback (< 5 min)
**Goal:** Catch the most common issues quickly

```yaml
# .github/workflows/quality.yml
name: Fast Quality Checks

on: [push, pull_request]

jobs:
  fast-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      # Re-run hook checks (in case bypassed)
      - name: Format check
        run: cargo fmt -- --check
      
      - name: Clippy
        run: cargo clippy --all-targets -- -D warnings
      
      - name: Unit tests
        run: cargo test --lib
      
      - name: Secrets scan
        run: |
          pip install detect-secrets
          detect-secrets scan
      
      - name: Dependency audit
        run: cargo audit
```

#### Tier 2: Comprehensive (< 15 min)
**Goal:** Thorough validation of correctness

```yaml
# .github/workflows/comprehensive.yml
name: Comprehensive Checks

on: [pull_request]

jobs:
  comprehensive:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      # Full test suite
      - name: All tests with coverage
        run: |
          cargo install cargo-tarpaulin
          cargo tarpaulin --out Xml --output-dir coverage
      
      - name: Coverage gate
        run: |
          coverage=$(xmllint --xpath "string(//coverage/@line-rate)" coverage/cobertura.xml)
          if (( $(echo "$coverage < 0.80" | bc -l) )); then
            echo "Coverage $coverage is below 80%"
            exit 1
          fi
      
      # Mutation testing
      - name: Mutation tests
        run: |
          cargo install cargo-mutants
          cargo mutants --no-shuffle -j 2
      
      # Integration tests
      - name: Integration tests
        run: cargo test --test '*'
      
      # Static analysis
      - name: SonarQube scan
        run: sonar-scanner
      
      # Architecture validation
      - name: Validate architecture
        run: ./scripts/validate-architecture.sh
```

#### Tier 3: Deep Analysis (can be slower)
**Goal:** Security, compliance, performance

```yaml
# .github/workflows/security.yml
name: Security & Compliance

on:
  pull_request:
  schedule:
    - cron: '0 0 * * 0'  # Weekly

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: CodeQL analysis
        uses: github/codeql-action/analyze@v2
      
      - name: Container scan
        run: trivy image myapp:latest
      
      - name: License compliance
        run: cargo deny check licenses
      
      - name: SBOM generation
        run: cargo sbom
```

### Architecture Compliance Script

**Purpose:** Validate code follows ADRs and constraints

```bash
#!/bin/bash
# scripts/validate-architecture.sh

set -e

echo "Validating architecture compliance..."

# Load tech decisions
if [ ! -f ".tech-decisions.yml" ]; then
    echo "No .tech-decisions.yml found, skipping"
    exit 0
fi

# Check forbidden patterns
echo "Checking for forbidden patterns..."

# Example: No SELECT * in production code
if grep -r "SELECT \*" src/ --include="*.rs" --exclude-dir=tests; then
    echo "Error: Found 'SELECT *' in production code"
    echo "See .tech-decisions.yml database.forbidden_operations"
    exit 1
fi

# Example: No hard-coded credentials
if grep -rE "(password|secret|key)\s*=\s*['\"]" src/ --include="*.rs"; then
    echo "Error: Possible hard-coded credential"
    exit 1
fi

# Check layer boundaries (example for Rust)
# Ensure domain layer doesn't depend on infrastructure
if grep -r "use.*infrastructure" src/domain/ --include="*.rs" 2>/dev/null; then
    echo "Error: Domain layer has infrastructure dependency"
    echo "This violates our clean architecture (see ADR-0003)"
    exit 1
fi

echo "✓ Architecture validation passed"
```

### Integration with Tech Decisions

```yaml
# Part of CI that validates against .tech-decisions.yml

- name: Validate tech decisions
  run: |
    # Check HTTP client usage
    allowed_client=$(yq '.http_client.rust' .tech-decisions.yml)
    if grep -r "use hyper::" src/ --include="*.rs"; then
      if [ "$allowed_client" != "hyper" ]; then
        echo "Using hyper but .tech-decisions.yml specifies $allowed_client"
        exit 1
      fi
    fi
    
    # Check testing coverage
    min_coverage=$(yq '.testing.unit_coverage_minimum' .tech-decisions.yml)
    actual_coverage=$(... extract from coverage report ...)
    if (( $(echo "$actual_coverage < $min_coverage" | bc -l) )); then
      echo "Coverage $actual_coverage% below minimum $min_coverage%"
      exit 1
    fi
```

---

## Language-Specific Configurations

### Rust

**Pre-commit checks:**
```bash
# Fast checks
cargo fmt -- --check
cargo clippy --all-targets -- -D warnings -W clippy::all

# Optional: quick compile check
cargo check --all-targets
```

**CI checks:**
```yaml
- name: Full test suite
  run: cargo test --all-features

- name: Coverage
  run: cargo tarpaulin --out Xml --all-features

- name: Mutation testing
  run: cargo mutants --in-place

- name: Audit dependencies
  run: cargo audit

- name: Check for unused dependencies
  run: cargo machete
```

**Standards file (`docs/standards/rust.md`):**
- Error handling: Use `thiserror` for errors, `anyhow` for applications
- Async: Use `tokio` runtime
- Logging: Use `tracing` with structured fields
- Testing: Use `rstest` for parameterized tests

### JavaScript/TypeScript

**Pre-commit checks:**
```bash
npx prettier --check .
npx eslint .
npx tsc --noEmit  # Type check without emit
```

**CI checks:**
```yaml
- name: Lint
  run: npm run lint

- name: Type check
  run: npm run type-check

- name: Tests with coverage
  run: npm test -- --coverage --coverageThreshold='{"global":{"lines":80}}'

- name: Mutation testing
  run: npx stryker run

- name: Bundle size check
  run: npm run build && bundlesize
```

### Python

**Pre-commit checks:**
```bash
black --check .
ruff check .
mypy src/
```

**CI checks:**
```yaml
- name: Lint and format
  run: |
    ruff check .
    black --check .
    mypy src/

- name: Tests with coverage
  run: |
    pytest --cov=src --cov-report=xml --cov-fail-under=80

- name: Mutation testing
  run: mutmut run

- name: Security check
  run: bandit -r src/
```

### .NET/C#

**Pre-commit checks:**
```powershell
dotnet format --verify-no-changes
dotnet build /p:TreatWarningsAsErrors=true
```

**CI checks:**
```yaml
- name: Build
  run: dotnet build -c Release

- name: Test with coverage
  run: dotnet test --collect:"XPlat Code Coverage" --logger trx

- name: Mutation testing
  run: dotnet stryker

- name: Security scan
  run: dotnet security-scan
```

---

## Maintenance and Evolution

### When to Update AI Memory

**Update `docs/constraints.md` when:**
- You catch a common mistake repeatedly
- A new "gotcha" is discovered
- A decision is made that affects multiple features

**Update `docs/catalog.md` when:**
- A new reusable component reaches stability
- An existing component's API changes
- A component is deprecated

**Create new ADR when:**
- Making an architectural decision (not just code-level)
- Choosing between multiple viable approaches
- Establishing a new pattern or constraint
- Deprecating an old decision

**Update `docs/standards/*.md` when:**
- Adopting a new tool or library as standard
- Changing code style conventions
- Updating security requirements
- Modifying the development process

### Keeping Checks Current

**Monthly review:**
1. Check if new security vulnerabilities require additional scans
2. Update dependency versions in CI
3. Review failed checks — are they catching real issues?
4. Look for patterns in bypassed hooks — why?

**Quarterly review:**
1. Assess mutation testing score trends
2. Review coverage trends
3. Update `.tech-decisions.yml` if tech stack evolved
4. Retire obsolete ADRs (mark as "Superseded")

### AI-Assisted Improvement

**Prompt for reviewing checks:**

```
Review our current pre-commit hooks in .githooks/ and CI in .github/workflows/quality.yml.

Based on:
- Recent failed builds (see logs)
- Common issues in recent PRs
- Our tech stack in .tech-decisions.yml
- Our constraints in docs/constraints.md

Suggest:
1. New checks we should add
2. Existing checks that are too slow/noisy
3. Better tools for our use cases
```

**Prompt for updating documentation:**

```
Our recent commits show we're using pattern X repeatedly (see git log --grep="X").

Review:
- Whether this should be in docs/catalog.md
- Whether this needs an ADR
- Whether docs/constraints.md should mention it

Suggest updates with diffs.
```

---

## Complete Setup Scripts

### Bootstrap Script (PowerShell)

**`scripts/bootstrap-ai-repo.ps1`:**

```powershell
<#
.SYNOPSIS
    Bootstrap AI-assisted development framework for a repository
.DESCRIPTION
    Sets up AI memory structure, commit hooks, and CI configuration
.PARAMETER Force
    Overwrite existing files
#>

param([switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)

Write-Host "Bootstrapping AI-assisted development framework..." -ForegroundColor Cyan

# Step 1: Create AI memory structure
Write-Host "`n[1/4] Creating AI memory structure..." -ForegroundColor Yellow
& "$root\scripts\create-llm-memory.ps1" $(if ($Force) { "-Force" })

# Step 2: Setup commit hooks
Write-Host "`n[2/4] Setting up commit hooks..." -ForegroundColor Yellow
& "$root\scripts\setup-hooks.ps1"

# Step 3: Detect languages and create .tech-decisions.yml
Write-Host "`n[3/4] Detecting tech stack..." -ForegroundColor Yellow
& "$root\scripts\detect-stack.ps1"

# Step 4: Create CI configuration
Write-Host "`n[4/4] Setting up CI..." -ForegroundColor Yellow
& "$root\scripts\setup-ci.ps1"

Write-Host "`n✓ Bootstrap complete!" -ForegroundColor Green
Write-Host "`nNext steps:"
Write-Host "  1. Review AGENTS.md for AI agent guidelines"
Write-Host "  2. Review docs/constraints.md and add project-specific rules"
Write-Host "  3. Create your first ADR in docs/adr/"
Write-Host "  4. Commit the new structure: git add . && git commit -m 'Add AI development framework'"
```

### Hook Setup Script (PowerShell)

**`scripts/setup-hooks.ps1`:**

```powershell
<#
.SYNOPSIS
    Install git hooks for AI-assisted development
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$hooksDir = Join-Path $root ".githooks"

Write-Host "Installing git hooks..." -ForegroundColor Cyan

# Verify .githooks directory exists
if (-not (Test-Path $hooksDir)) {
    Write-Host "Error: .githooks directory not found" -ForegroundColor Red
    Write-Host "Expected location: $hooksDir"
    exit 1
}

# Configure git to use .githooks
try {
    git config core.hooksPath .githooks
    Write-Host "✓ Git configured to use .githooks/" -ForegroundColor Green
} catch {
    Write-Host "Error configuring git hooks: $_" -ForegroundColor Red
    exit 1
}

# Make hooks executable (if on Windows with WSL or Git Bash)
if (Get-Command "chmod" -ErrorAction SilentlyContinue) {
    Get-ChildItem $hooksDir -File | ForEach-Object {
        chmod +x $_.FullName
    }
    Write-Host "✓ Made hooks executable" -ForegroundColor Green
}

# Verify hooks
$hookFiles = @("pre-commit", "commit-msg")
$missing = @()

foreach ($hook in $hookFiles) {
    $hookPath = Join-Path $hooksDir $hook
    if (-not (Test-Path $hookPath)) {
        $missing += $hook
    }
}

if ($missing.Count -gt 0) {
    Write-Host "Warning: Missing hooks: $($missing -join ', ')" -ForegroundColor Yellow
    Write-Host "Create these in .githooks/ directory"
}

Write-Host "`n✓ Hooks installed successfully!" -ForegroundColor Green
Write-Host "`nHooks will run automatically on:"
Write-Host "  • pre-commit: Before creating a commit"
Write-Host "  • commit-msg: After writing commit message"
Write-Host "`nTo bypass (not recommended): git commit --no-verify"
```

### Tech Stack Detection

**`scripts/detect-stack.ps1`:**

```powershell
<#
.SYNOPSIS
    Detect tech stack and create .tech-decisions.yml
#>

Set-StrictMode -Version Latest

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)

Write-Host "Detecting tech stack..." -ForegroundColor Cyan

$languages = @()
$tools = @{}

# Detect Rust
if (Test-Path "$root/Cargo.toml") {
    $languages += "rust"
    $tools["rust"] = @{
        formatter = "cargo fmt"
        linter = "cargo clippy"
        test_runner = "cargo test"
    }
}

# Detect JavaScript/TypeScript
if (Test-Path "$root/package.json") {
    $languages += "javascript"
    $packageJson = Get-Content "$root/package.json" | ConvertFrom-Json
    
    $hasTypeScript = (Test-Path "$root/tsconfig.json") -or 
                     ($packageJson.devDependencies -and $packageJson.devDependencies.typescript)
    
    if ($hasTypeScript) {
        $languages += "typescript"
    }
    
    $tools["javascript"] = @{
        formatter = "prettier"
        linter = "eslint"
        test_runner = "jest"
    }
}

# Detect Python
if ((Test-Path "$root/setup.py") -or (Test-Path "$root/pyproject.toml")) {
    $languages += "python"
    $tools["python"] = @{
        formatter = "black"
        linter = "ruff"
        type_checker = "mypy"
        test_runner = "pytest"
    }
}

# Create .tech-decisions.yml
$content = @"
# Tech Stack Configuration
# Generated: $(Get-Date -Format "yyyy-MM-dd")
# This file is read by CI and commit hooks to enforce standards

languages: [$(($languages | ForEach-Object { "'$_'" }) -join ", ")]

# TODO: Fill in your specific choices
database:
  choice: null  # e.g., postgresql, mongodb
  rationale: "See docs/adr/ADR-XXXX.md"

# Testing requirements
testing:
  unit_coverage_minimum: 80
  mutation_score_minimum: 70
  integration_test_required_for:
    - "API endpoints"
    - "Database changes"

# Code quality
code_quality:
  max_function_length: 50
  max_file_length: 500
  max_complexity: 10
  no_duplicate_blocks: true

# Infrastructure (if applicable)
infrastructure:
  deployment: null  # e.g., kubernetes, lambda, vm
  always:
    - "Include health checks"
    - "Set resource limits"
  never:
    - "Hard-code credentials"
    - "Use 'latest' tag in production"
"@

$techFile = Join-Path $root ".tech-decisions.yml"
if ((Test-Path $techFile) -and -not $Force) {
    Write-Host "Skipping .tech-decisions.yml (already exists)" -ForegroundColor Yellow
} else {
    $content | Out-File -FilePath $techFile -Encoding UTF8
    Write-Host "✓ Created .tech-decisions.yml" -ForegroundColor Green
}

Write-Host "`nDetected languages: $($languages -join ', ')"
Write-Host "Review and customize .tech-decisions.yml"
```

---

## Summary

This framework provides:

1. **AI Memory** — Structured documentation that AIs can read to understand project context
2. **Fast Feedback** — Pre-commit hooks catch obvious mistakes in seconds
3. **Authoritative Validation** — CI enforces quality standards comprehensively
4. **Progressive Enhancement** — Easy to start, grows with project complexity
5. **Maintainability** — Clear ownership of where decisions live

**Key principles:**

- **Make it easy to do the right thing** — Automate as much as possible
- **Trust but verify** — Hooks are advisory, CI is authoritative
- **Documentation is code** — Keep it in version control, update it regularly
- **AI-friendly by design** — Structured, machine-readable, with clear entry points

**Getting started:**

```bash
# 1. Bootstrap
./scripts/bootstrap-ai-repo.sh

# 2. Customize
#    - Edit docs/constraints.md with your project rules
#    - Fill in .tech-decisions.yml
#    - Create your first ADR

# 3. Commit
git add .
git commit -m "Add AI development framework"
```

Your AI agents now have context, and your repository has guardrails. Quality maintained, velocity preserved.
