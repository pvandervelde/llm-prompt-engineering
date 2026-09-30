#!/bin/bash
# Bootstrap AI-assisted development framework for a repository
# Usage: ./bootstrap-ai-repo.sh [--force]

set -e

# Parse arguments
FORCE=0
if [[ "$1" == "--force" ]]; then
    FORCE=1
fi

# Get script directory and repo root
# This script lives two levels below the repo root (tools/ai-bootstrap/), so
# ROOT needs to go up two levels, not one.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  AI-Assisted Development Framework Bootstrap              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
}

function print_step() {
    echo -e "\n${YELLOW}$1${NC}"
}

function print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

function print_info() {
    echo -e "  ${BLUE}$1${NC}"
}

function print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

function print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_header

# Verify we're in a git repository
if [ ! -d "$ROOT/.git" ]; then
    print_error "Not in a git repository. Initialize git first: git init"
    exit 1
fi

# ============================================================================
# Step 1: Create AI Memory Structure
# ============================================================================
print_step "[1/5] Creating AI memory structure..."

MEMORY_SCRIPT="$SCRIPT_DIR/create-llm-memory.sh"
if [ -f "$MEMORY_SCRIPT" ]; then
    if [ $FORCE -eq 1 ]; then
        "$MEMORY_SCRIPT" --force
    else
        "$MEMORY_SCRIPT"
    fi
    print_success "AI memory structure created"
else
    print_warning "create-llm-memory.sh not found, creating minimal structure..."

    # Create minimal structure
    mkdir -p "$ROOT/docs/adr"
    mkdir -p "$ROOT/docs/standards"
    mkdir -p "$ROOT/.githooks"

    print_success "Minimal directory structure created"
fi

# ============================================================================
# Step 2: Create Git Hooks
# ============================================================================
print_step "[2/5] Creating git hooks..."

HOOKS_DIR="$ROOT/.githooks"
mkdir -p "$HOOKS_DIR"

# Create pre-commit hook
cat > "$HOOKS_DIR/pre-commit" << 'HOOK_EOF'
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
if ls *.csproj >/dev/null 2>&1 || ls *.sln >/dev/null 2>&1; then
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
HOOK_EOF

chmod +x "$HOOKS_DIR/pre-commit"
print_success "Created pre-commit hook"

# Create commit-msg hook
cat > "$HOOKS_DIR/commit-msg" << 'HOOK_EOF'
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
HOOK_EOF

chmod +x "$HOOKS_DIR/commit-msg"
print_success "Created commit-msg hook"

# Configure git to use .githooks
git config core.hooksPath .githooks
print_success "Git configured to use .githooks/"

# ============================================================================
# Step 3: Detect Tech Stack
# ============================================================================
print_step "[3/5] Detecting tech stack..."

LANGUAGES=()

# Detect Rust
if [ -f "$ROOT/Cargo.toml" ]; then
    LANGUAGES+=("rust")
    print_info "Detected: Rust"
fi

# Detect JavaScript/TypeScript
if [ -f "$ROOT/package.json" ]; then
    LANGUAGES+=("javascript")
    print_info "Detected: JavaScript"

    if [ -f "$ROOT/tsconfig.json" ]; then
        LANGUAGES+=("typescript")
        print_info "Detected: TypeScript"
    fi
fi

# Detect Python
if [ -f "$ROOT/setup.py" ] || [ -f "$ROOT/pyproject.toml" ] || [ -f "$ROOT/requirements.txt" ]; then
    LANGUAGES+=("python")
    print_info "Detected: Python"
fi

# Detect .NET
if ls "$ROOT"/*.csproj >/dev/null 2>&1 || ls "$ROOT"/*.sln >/dev/null 2>&1; then
    LANGUAGES+=("csharp")
    print_info "Detected: C#/.NET"
fi

# Detect Go
if [ -f "$ROOT/go.mod" ]; then
    LANGUAGES+=("go")
    print_info "Detected: Go"
fi

print_success "Tech stack detection complete"

# ============================================================================
# Step 4: Create .tech-decisions.yml
# ============================================================================
print_step "[4/5] Creating .tech-decisions.yml..."

TECH_FILE="$ROOT/.tech-decisions.yml"
if [ -f "$TECH_FILE" ] && [ $FORCE -eq 0 ]; then
    print_warning ".tech-decisions.yml already exists (use --force to overwrite)"
else
    # Convert array to comma-separated string
    LANGS_STR=$(IFS=, ; echo "${LANGUAGES[*]}")

    # Resolve default toolchain from detected languages
    TOOLCHAIN_DEFAULT="null"
    for lang in "${LANGUAGES[@]}"; do
        case $lang in
            rust) TOOLCHAIN_DEFAULT="rust"; break ;;
            csharp) TOOLCHAIN_DEFAULT="dotnet"; break ;;
            typescript) TOOLCHAIN_DEFAULT="typescript"; break ;;
            javascript) [ "$TOOLCHAIN_DEFAULT" = "null" ] && TOOLCHAIN_DEFAULT="typescript" ;;
        esac
    done

    cat > "$TECH_FILE" << EOF
# Technology Decisions and Standards
# Generated: $(date +%Y-%m-%d)
# This file is read by CI and commit hooks to enforce standards

# Detected languages
languages: [$LANGS_STR]

# Toolchain resolution layer. Agents describe what they need in abstract
# capability terms (test, mutation, fuzz, formal, ...); the Tech Lead resolves
# this block to concrete commands for the active stack and injects them into
# every subagent prompt as a \`## Toolchain\` block. Mutation scores are NOT
# comparable across engines - see mutation_targets below.
toolchains:
  default: $TOOLCHAIN_DEFAULT

  detect:
    - if_exists: "Cargo.toml"
      toolchain: rust
    - if_exists: "*.csproj|*.sln"
      toolchain: dotnet
    - if_exists: "package.json"
      toolchain: typescript
    - if_exists: "pyproject.toml"
      toolchain: python  # no toolchain block defined yet - add one before use

  rust:
    build:             "cargo build --workspace"
    typecheck:         "cargo check --workspace"
    test:              "cargo test --workspace"
    test_scoped:       "cargo test -p {package}"
    lint:              "cargo clippy -- -D warnings"
    format_check:      "cargo fmt --check"
    coverage:          "cargo llvm-cov --json --output-path {out}"
    mutation:          "cargo mutants --package {package} --timeout 60 --json"
    mutation_engine:   "cargo-mutants"
    fuzz_list:         "cargo fuzz list"
    fuzz_run:          "cargo fuzz run {target} -- -max_total_time={seconds}"
    fuzz_add:          "cargo fuzz add {target}"
    formal:            "cargo kani --package {package}"
    property_lib:      "proptest"
    structural_search: "ast-grep --lang rust"
    test_paths:        ["tests/", "src/**/tests.rs", "src/**/*_test.rs"]

  dotnet:
    build:             "dotnet build"
    typecheck:         "dotnet build --no-restore /p:TreatWarningsAsErrors=true"
    test:              "dotnet test"
    test_scoped:       "dotnet test {package}"
    lint:              "dotnet format --verify-no-changes && dotnet roslynator analyze"
    format_check:      "dotnet format --verify-no-changes"
    coverage:          "dotnet test --collect:'XPlat Code Coverage'"
    mutation:          "dotnet stryker --project {package} --reporter json --output {out}"
    mutation_engine:   "stryker-net"
    fuzz_list:         "ls fuzz/"
    fuzz_run:          "dotnet run --project fuzz/{target} -- -max_total_time={seconds}"
    fuzz_add:          null
    formal:            null
    property_lib:      "CsCheck"
    structural_search: "ast-grep --lang csharp"
    test_paths:        ["**/*.Tests/", "**/*Tests.cs"]

  typescript:
    build:             "npm run build"
    typecheck:         "tsc --noEmit"
    test:              "npx vitest run"
    test_scoped:       "npx vitest run {package}"
    lint:              "npx eslint . --max-warnings 0"
    format_check:      "npx prettier --check ."
    coverage:          "npx vitest run --coverage --reporter=json"
    mutation:          "npx stryker run --mutate '{package}/**/*.ts' --reporters json"
    mutation_engine:   "stryker-js"
    fuzz_list:         "ls fuzz/"
    fuzz_run:          "npx jazzer fuzz/{target} -- -max_total_time={seconds}"
    fuzz_add:          null
    formal:            null
    property_lib:      "fast-check"
    structural_search: "ast-grep --lang typescript"
    test_paths:        ["**/*.test.ts", "**/*.spec.ts", "tests/"]

# Mutation targets are per-engine because operator sets and denominators differ
# and scores are not comparable across engines.
mutation_targets:
  cargo-mutants:
    safety_critical: 95
    domain_logic:    85
    parser:          80
    api_boundary:    80
    adapter:         70
  stryker-net:
    safety_critical: 90
    domain_logic:    80
    parser:          75
    api_boundary:    75
    adapter:         65
  stryker-js:
    safety_critical: 90
    domain_logic:    80
    parser:          75
    api_boundary:    75
    adapter:         65

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
EOF

    # Add language-specific HTTP clients
    for lang in "${LANGUAGES[@]}"; do
        case $lang in
            rust)
                echo "  rust: reqwest  # Standard HTTP client for Rust" >> "$TECH_FILE"
                ;;
            python)
                echo "  python: httpx  # Async-first HTTP client" >> "$TECH_FILE"
                ;;
            javascript)
                echo "  javascript: axios  # Standard for Node.js" >> "$TECH_FILE"
                ;;
        esac
    done

    cat >> "$TECH_FILE" << 'EOF'
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

# Code quality standards
code_quality:
  max_function_length: 50
  max_file_length: 500
  max_complexity: 10
  no_duplicate_blocks: true

# Security standards
security:
  secret_management: "environment variables or secret manager"
  no_hardcoded_secrets: true
  dependency_scanning:
    enabled: true
    fail_on: "high"

# Infrastructure standards
infrastructure:
  deployment: null
  always:
    - "Include health check endpoint"
    - "Set resource limits"
  never:
    - "Hard-code credentials"
    - "Use 'latest' tag in production"
EOF

    print_success "Created .tech-decisions.yml"
fi

# ============================================================================
# Step 5: Setup Beads (Optional Task Tracking)
# ============================================================================
print_step "[5/6] Setting up Beads task tracking (optional)..."

if command -v bd >/dev/null 2>&1; then
    print_info "Beads already installed"

    # Initialize Beads in the repo
    cd "$ROOT"
    if bd init 2>/dev/null; then
        print_success "Initialized Beads task tracking"

        # Update AGENTS.md with task tracking section
        AGENTS_FILE="$ROOT/AGENTS.md"
        if [ -f "$AGENTS_FILE" ]; then
            cat >> "$AGENTS_FILE" << 'BEADS_SECTION'


## Task Management

This project uses Beads (bd) for AI-friendly task tracking.

### Before starting work

1. Check what's ready: `bd ready --json`
2. Pick a task: `bd show bd-abc --json`
3. Start work: `bd update bd-abc working`

### When creating new tasks

1. Create issue: `bd create "Task description" -p 1 -t feature`
2. Add dependencies: `bd update bd-xyz --blocks bd-abc`
3. The task will auto-appear in `bd ready` when blockers are done

### When finishing work

1. Commit with issue ID: `git commit -m "Fix auth bug (bd-abc)"`
2. Close issue: `bd close bd-abc --reason "Completed"`
3. Sync: `bd sync` (usually automatic)

### Integration with ADRs

- Link ADRs in task descriptions: "See ADR-0005 for context"
- Create tasks for implementing ADR decisions
- Reference task IDs in ADR implementation notes

### Quick reference

```bash
bd ready              # Show tasks ready to work on
bd create "desc" -p 1 # Create new task (priority 1-5)
bd show bd-xyz        # Show task details
bd update bd-xyz working  # Mark task in progress
bd close bd-xyz       # Close completed task
bd search "keyword"   # Search tasks
bd doctor             # Check for orphaned work
```
BEADS_SECTION
            print_success "Updated AGENTS.md with task tracking guidance"
        fi

        # Update .tech-decisions.yml with task tracking config
        TECH_FILE="$ROOT/.tech-decisions.yml"
        if [ -f "$TECH_FILE" ]; then
            cat >> "$TECH_FILE" << 'TECH_SECTION'

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
TECH_SECTION
            print_success "Updated .tech-decisions.yml with task tracking config"
        fi

        # Create initial setup tasks
        print_info "Creating initial framework setup tasks..."
        bd create "Customize docs/constraints.md with project-specific rules" -p 1 -t docs >/dev/null 2>&1
        bd create "Fill in .tech-decisions.yml with actual tech choices" -p 1 -t docs >/dev/null 2>&1
        bd create "Create first ADR documenting initial architectural decision" -p 2 -t docs >/dev/null 2>&1
        bd create "Review and customize pre-commit hooks for project needs" -p 3 -t infrastructure >/dev/null 2>&1

        print_info "Created 4 initial setup tasks. Run 'bd ready' to see them."
    else
        print_warning "Failed to initialize Beads"
    fi
else
    print_warning "Beads not installed. Task tracking is optional but recommended."
    echo ""
    print_info "To install Beads and enable task tracking:"
    print_info "  curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash"
    print_info "  Then run: bd init"
    echo ""
    print_info "Benefits of Beads:"
    print_info "  • AI-friendly task tracking with JSON output"
    print_info "  • Dependency management (what's blocking what)"
    print_info "  • Git-versioned (no external services needed)"
    print_info "  • Multi-agent coordination safe"
    echo ""
    print_info "In the meantime, AI modes will use ./.llm/tasks.md for task tracking."
fi

# ============================================================================
# Step 5b: Initialize Fallback Task Structure
# ============================================================================
print_step "[5b/6] Initializing fallback task structure (.llm/tasks.md)..."

LLM_DIR="$ROOT/.llm"
if [ ! -d "$LLM_DIR" ]; then
    mkdir -p "$LLM_DIR"
    print_success "Created .llm directory"
fi

# Create a template tasks.md if it doesn't exist
TASKS_FILE="$LLM_DIR/tasks.md"
if [ ! -f "$TASKS_FILE" ]; then
    cat > "$TASKS_FILE" << 'TASKS_EOF'
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
TASKS_EOF
    print_success "Created .llm/tasks.md template"
else
    print_info ".llm/tasks.md already exists (skipped)"
fi

# ============================================================================
# Step 5c: Deploy Task Sync Helper Scripts
# ============================================================================
# .llm/tasks.md (above) tells agents to run scripts/tasks-export.sh or
# scripts/tasks-export.ps1 to sync Markdown tasks to JSON. Those scripts only
# exist in the llm-prompt-engineering source repo, not in the repo being
# bootstrapped — an agent reading that note on a fresh target repo would find
# nothing there. Generate both variants directly so the target repo is
# self-contained and doesn't depend on anything outside itself.
print_step "[5c/6] Deploying task sync helper scripts..."

SCRIPTS_DIR="$ROOT/scripts"
mkdir -p "$SCRIPTS_DIR"

TASKS_EXPORT_SH="$SCRIPTS_DIR/tasks-export.sh"
if [ -f "$TASKS_EXPORT_SH" ] && [ $FORCE -eq 0 ]; then
    print_warning "scripts/tasks-export.sh already exists (use --force to overwrite)"
else
    cat > "$TASKS_EXPORT_SH" << 'TASKS_EXPORT_SH_EOF'
#!/bin/bash

# Export tasks from Markdown to JSON format
# Converts ./.llm/tasks.md to ./.llm/tasks.json following the task-sources contract

TASKS_FILE="${1:-./.llm/tasks.md}"
OUTPUT_FILE="${2:-./.llm/tasks.json}"

# Check if the input file exists
if [ ! -f "$TASKS_FILE" ]; then
    echo "Error: Task file not found: $TASKS_FILE" >&2
    exit 1
fi

# Parse Markdown checklist and convert to JSON
TASKS_JSON='{"tasks":['
TASK_ID=0
FIRST_TASK=true

while IFS= read -r line; do
    # Match checklist items: - [ ] or - [x]
    if [[ $line =~ ^[[:space:]]*-[[:space:]]+\[([[:space:]xX])\][[:space:]]+(.+)$ ]]; then
        TASK_ID=$((TASK_ID + 1))
        CHECKED="${BASH_REMATCH[1]}"
        TITLE="${BASH_REMATCH[2]}"

        # Determine status based on checkbox
        if [[ "$CHECKED" == "x" || "$CHECKED" == "X" ]]; then
            STATUS="completed"
            CHECKED_VAL="true"
        else
            STATUS="open"
            CHECKED_VAL="false"
        fi

        # Escape special characters in title
        TITLE=$(printf '%s\n' "$TITLE" | sed 's/[\"\\]/\\&/g')

        # Add comma before new task (except first)
        if [ "$FIRST_TASK" = false ]; then
            TASKS_JSON="$TASKS_JSON,"
        fi
        FIRST_TASK=false

        # Add task object
        TASKS_JSON="$TASKS_JSON{\"id\":\"task-$TASK_ID\",\"title\":\"$TITLE\",\"description\":\"\",\"status\":\"$STATUS\",\"checked\":$CHECKED_VAL}"
    fi
done < "$TASKS_FILE"

TASKS_JSON="$TASKS_JSON]}"

# Write to output file
if ! echo "$TASKS_JSON" > "$OUTPUT_FILE"; then
    echo "Error: Failed to write to $OUTPUT_FILE" >&2
    exit 1
fi

echo "Successfully exported $TASK_ID task(s) to $OUTPUT_FILE"
exit 0
TASKS_EXPORT_SH_EOF
    chmod +x "$TASKS_EXPORT_SH"
    print_success "Created scripts/tasks-export.sh"
fi

TASKS_EXPORT_PS1="$SCRIPTS_DIR/tasks-export.ps1"
if [ -f "$TASKS_EXPORT_PS1" ] && [ $FORCE -eq 0 ]; then
    print_warning "scripts/tasks-export.ps1 already exists (use --force to overwrite)"
else
    cat > "$TASKS_EXPORT_PS1" << 'TASKS_EXPORT_PS1_EOF'
# Export tasks from Markdown to JSON format
# Converts ./.llm/tasks.md to ./.llm/tasks.json following the task-sources contract

param(
    [string]$TasksFile = ".\.llm\tasks.md",
    [string]$OutputFile = ".\.llm\tasks.json"
)

# Check if the input file exists
if (-not (Test-Path $TasksFile)) {
    Write-Error "Task file not found: $TasksFile"
    exit 1
}

# Read the Markdown file
try {
    $content = Get-Content $TasksFile -Raw
} catch {
    Write-Error "Failed to read $TasksFile : $_"
    exit 1
}

# Parse Markdown checklist and convert to JSON
$tasks = @()
$taskId = 0
$lines = $content -split "`n"

foreach ($line in $lines) {
    # Match checklist items: - [ ] or - [x]
    if ($line -match '^\s*-\s+\[([ xX])\]\s+(.+)') {
        $checked = $matches[1] -eq 'x' -or $matches[1] -eq 'X'
        $title = $matches[2].Trim()
        $taskId++

        $task = @{
            id       = "task-$taskId"
            title    = $title
            description = ""
            status   = if ($checked) { "completed" } else { "open" }
            checked  = $checked
        }

        $tasks += $task
    }
}

# Create the JSON structure
$jsonObject = @{
    tasks = $tasks
}

# Convert to JSON and write to output file
try {
    $jsonContent = $jsonObject | ConvertTo-Json -Depth 10
    Set-Content -Path $OutputFile -Value $jsonContent -Encoding UTF8
    Write-Output "Successfully exported $($tasks.Count) task(s) to $OutputFile"
    exit 0
} catch {
    Write-Error "Failed to write to $OutputFile : $_"
    exit 1
}
TASKS_EXPORT_PS1_EOF
    print_success "Created scripts/tasks-export.ps1"
fi

# ============================================================================
# Step 6: Create CI Configuration
# ============================================================================
print_step "[6/6] Creating CI configuration..."

mkdir -p "$ROOT/.github/workflows"
CI_FILE="$ROOT/.github/workflows/quality.yml"

if [ -f "$CI_FILE" ] && [ $FORCE -eq 0 ]; then
    print_warning "quality.yml already exists (use --force to overwrite)"
else
    cat > "$CI_FILE" << 'EOF'
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

      - name: Check for secrets
        run: |
          pip install detect-secrets
          if [ -f ".secrets.baseline" ]; then
            detect-secrets scan --baseline .secrets.baseline
          fi
EOF

    # Add language-specific checks
    for lang in "${LANGUAGES[@]}"; do
        case $lang in
            rust)
                cat >> "$CI_FILE" << 'EOF'

      - name: Rust - Setup
        uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
          components: rustfmt, clippy

      - name: Rust - Format check
        run: cargo fmt -- --check

      - name: Rust - Clippy
        run: cargo clippy --all-targets -- -D warnings

      - name: Rust - Unit tests
        run: cargo test --lib
EOF
                ;;
            javascript|typescript)
                cat >> "$CI_FILE" << 'EOF'

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

      - name: Node - Unit tests
        run: npm test
EOF
                ;;
            python)
                cat >> "$CI_FILE" << 'EOF'

      - name: Python - Setup
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Python - Install dependencies
        run: |
          pip install black ruff pytest
          if [ -f requirements.txt ]; then pip install -r requirements.txt; fi

      - name: Python - Format check
        run: black --check .

      - name: Python - Lint
        run: ruff check .

      - name: Python - Unit tests
        run: pytest tests/
EOF
                ;;
        esac
    done

    print_success "Created .github/workflows/quality.yml"
fi

# Create pipeline-gates.yml — the seven required checks the agent pipeline's own gates
# (RED/GREEN integrity, mutation targets, security findings, evidence presence) rely on.
# These read the same .tech-decisions.yml thresholds and .llm/evidence/ artefacts the
# agents produce, so the gate that blocks merge is a branch protection rule, not an
# agent's self-report. Wire these as required status checks on your default branch —
# this script does not modify branch protection itself (a repo-admin action).
PIPELINE_GATES_FILE="$ROOT/.github/workflows/pipeline-gates.yml"
if [ -f "$PIPELINE_GATES_FILE" ] && [ $FORCE -eq 0 ]; then
    print_warning "pipeline-gates.yml already exists (use --force to overwrite)"
else
    cat > "$PIPELINE_GATES_FILE" << 'EOF'
name: Pipeline Gates

on:
  pull_request:
    branches: [main, master]

permissions:
  contents: read

jobs:
  spec-assertion-coverage:
    name: spec/assertion-coverage
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Every active assertion has a matching test name
        run: |
          set -euo pipefail
          if [ ! -f docs/spec/assertions.md ]; then
            echo "No docs/spec/assertions.md yet — nothing to enforce"
            exit 0
          fi
          ids=$(grep -oE '^### ASSERT-[0-9]{4}' docs/spec/assertions.md | grep -oE 'ASSERT-[0-9]{4}' | sort -u)
          missing=0
          for id in $ids; do
            lower=$(echo "$id" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
            if ! grep -rIlE "(${id}|${lower})" -- . >/dev/null 2>&1; then
              echo "::error::No test references $id"
              missing=1
            fi
          done
          exit $missing

  spec-traceability:
    name: spec/traceability
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Every task references a valid assertion ID
        run: |
          set -euo pipefail
          if [ ! -f .llm/tasks.md ]; then
            echo "No .llm/tasks.md yet — nothing to enforce"
            exit 0
          fi
          valid=$(grep -oE 'ASSERT-[0-9]{4}' docs/spec/assertions.md 2>/dev/null | sort -u || true)
          bad=0
          for id in $(grep -oE 'ASSERT-[0-9]{4}' .llm/tasks.md | sort -u); do
            if ! printf '%s\n' "$valid" | grep -qx "$id"; then
              echo "::error::.llm/tasks.md references $id, which does not exist in docs/spec/assertions.md"
              bad=1
            fi
          done
          exit $bad

  test-red-green-integrity:
    name: test/red-green-integrity
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Test files unchanged between RED and GREEN commits
        run: |
          set -euo pipefail
          base=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
          red=$(git log --format=%H --grep='^test:' -n1 "origin/$base"..HEAD || true)
          green=$(git log --format=%H --grep='^feat:\|^fix:' -n1 "origin/$base"..HEAD || true)
          if [ -z "$red" ] || [ -z "$green" ]; then
            echo "No RED/GREEN commit pair on this branch — skipping"
            exit 0
          fi
          if ! git diff --quiet "$red" "$green" -- tests/ '*.test.ts' '*.test.js' '*.spec.ts' '*.spec.js' '*Tests.cs' '*_test.go' 'test_*.py'; then
            echo "::error::Test files changed between the RED commit ($red) and the GREEN commit ($green)"
            exit 1
          fi

  quality-mutation:
    name: quality/mutation
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Mutation score meets the per-engine target for changed modules
        run: |
          set -euo pipefail
          sha=$(git rev-parse --short HEAD)
          report=".llm/evidence/mutation-${sha}.json"
          if [ ! -f "$report" ]; then
            echo "::error::No mutation report at $report for HEAD — QA Engineer audit evidence is missing"
            exit 1
          fi
          # Report shape varies by mutation_engine (cargo-mutants / stryker-net / stryker-js).
          # This checks the common case: a "modules" array with name/score/target per entry.
          # Adjust the jq filter below to match your engine's actual report schema.
          fail=0
          while IFS=$'\t' read -r module score target; do
            [ -z "$module" ] && continue
            awk -v s="$score" -v t="$target" 'BEGIN { exit !(s+0 < t+0) }' && {
              echo "::error::$module mutation score ${score}% is below target ${target}%"
              fail=1
            }
          done < <(jq -r '.modules[]? | [.name, .score, .target] | @tsv' "$report" 2>/dev/null || true)
          exit $fail

  quality-coverage-ratchet:
    name: quality/coverage-ratchet
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Coverage not below the merge-base value
        run: |
          set -euo pipefail
          baseline=".llm/evidence/coverage-baseline.json"
          current=".llm/evidence/coverage-current.json"
          if [ ! -f "$baseline" ] || [ ! -f "$current" ]; then
            echo "No baseline/current coverage evidence yet — nothing to ratchet against"
            exit 0
          fi
          base_pct=$(jq -r '.line_coverage' "$baseline")
          cur_pct=$(jq -r '.line_coverage' "$current")
          awk -v c="$cur_pct" -v b="$base_pct" 'BEGIN { exit !(c+0 < b+0) }' && {
            echo "::error::Coverage dropped from ${base_pct}% to ${cur_pct}% — ratchet only moves up"
            exit 1
          }

  security-findings:
    name: security/findings
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: No unresolved Critical or High findings
        run: |
          set -euo pipefail
          if ls .llm/findings/*.md >/dev/null 2>&1 && grep -rE '\[(CRITICAL|HIGH)\]' .llm/findings/*.md; then
            echo "::error::Unresolved Critical/High findings in .llm/findings/ — resolve before merge"
            exit 1
          fi

  evidence-present:
    name: evidence/present
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Every referenced evidence artefact exists and matches HEAD's SHA
        run: |
          set -euo pipefail
          sha=$(git rev-parse --short HEAD)
          state=".llm/workflow-state.md"
          if [ ! -f "$state" ]; then
            echo "No .llm/workflow-state.md — nothing to check"
            exit 0
          fi
          missing=0
          for path in $(grep -oE '\.llm/evidence/[A-Za-z0-9_./-]+' "$state" | sort -u); do
            if [ ! -e "$path" ]; then
              echo "::error::$path is referenced in workflow state but does not exist"
              missing=1
              continue
            fi
            case "$path" in
              *"$sha"*) : ;;
              *) echo "::error::$path does not match HEAD's SHA ($sha) — stale evidence"; missing=1 ;;
            esac
          done
          exit $missing
EOF

    print_success "Created .github/workflows/pipeline-gates.yml"
fi

# Create release-snapshot.yml — on merge to main/master, snapshot docs/spec/ plus
# assertion/traceability/mutation/security evidence into .llm/evidence/releases/<version>/.
# This is the artefact an auditor (62443-4-1, SSDF) actually wants: "the spec as it stood
# at release" without reconstructing it from git log.
RELEASE_SNAPSHOT_FILE="$ROOT/.github/workflows/release-snapshot.yml"
if [ -f "$RELEASE_SNAPSHOT_FILE" ] && [ $FORCE -eq 0 ]; then
    print_warning "release-snapshot.yml already exists (use --force to overwrite)"
else
    cat > "$RELEASE_SNAPSHOT_FILE" << 'EOF'
name: Release Snapshot

on:
  push:
    branches: [main, master]

permissions:
  contents: write

jobs:
  snapshot:
    name: Spec and evidence snapshot
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Build release snapshot
        run: |
          set -euo pipefail
          sha=$(git rev-parse --short HEAD)
          version=$(git describe --tags --always)
          out=".llm/evidence/releases/${version}"
          mkdir -p "$out"

          # 1. docs/spec/ as it stood at this merge commit
          if [ -d docs/spec ]; then
            tar -czf "$out/spec-snapshot.tar.gz" docs/spec
          fi

          # 2. Active assertions only, with IDs (skip anything marked deprecated)
          if [ -f docs/spec/assertions.md ]; then
            awk '
              /^### ASSERT-[0-9]{4}/ {
                if (block != "" && !deprecated) printf "%s", block
                block=$0 "\n"; deprecated=0; next
              }
              { block = block $0 "\n" }
              /\*\*Status:\*\* deprecated/ { deprecated=1 }
              END { if (block != "" && !deprecated) printf "%s", block }
            ' docs/spec/assertions.md > "$out/assertions-active.md"
          else
            touch "$out/assertions-active.md"
          fi

          # 3. Traceability: assertion_id, test_name, task_id, commit
          echo "assertion_id,test_name,task_id,commit" > "$out/traceability.csv"
          if [ -f docs/spec/assertions.md ]; then
            active_ids=$(awk '
              /^### ASSERT-[0-9]{4}/ {
                if (id != "" && !deprecated) print id
                match($0, /ASSERT-[0-9]{4}/); id=substr($0, RSTART, RLENGTH); deprecated=0
              }
              /\*\*Status:\*\* deprecated/ { deprecated=1 }
              END { if (id != "" && !deprecated) print id }
            ' docs/spec/assertions.md)

            if [ -f .llm/tasks.md ]; then
              awk '
                /^- \[[ xX]\] [0-9]+(\.[0-9]+)?/ { match($0, /[0-9]+(\.[0-9]+)?/); task=substr($0, RSTART, RLENGTH) }
                /Assertions:/ {
                  line=$0
                  while (match(line, /ASSERT-[0-9]{4}/)) {
                    id=substr(line, RSTART, RLENGTH)
                    print id "|" task
                    line=substr(line, RSTART+RLENGTH)
                  }
                }
              ' .llm/tasks.md > /tmp/assert-task-map.txt
            else
              : > /tmp/assert-task-map.txt
            fi

            for id in $active_ids; do
              lower=$(echo "$id" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
              test_names=$(grep -rlE "(${id}|${lower})" \
                --include='*test*' --include='*spec*' --include='*Tests.cs' --include='*_test.go' \
                -- . 2>/dev/null | tr '\n' ';' || true)
              task_id=$(grep "^${id}|" /tmp/assert-task-map.txt | cut -d'|' -f2 | paste -sd ';' -)
              echo "${id},\"${test_names}\",${task_id},${sha}" >> "$out/traceability.csv"
            done
          fi

          # 4. Mutation evidence already produced by QA Engineer for this commit
          if [ -f ".llm/evidence/mutation-${sha}.json" ]; then
            cp ".llm/evidence/mutation-${sha}.json" "$out/mutation-${sha}.json"
          fi

          # 5. Latest security report
          latest_security=$(ls -t .llm/security-review/*.md 2>/dev/null | head -1 || true)
          if [ -n "$latest_security" ]; then
            cp "$latest_security" "$out/security-report.md"
          fi

          # 6. Manifest: tool versions, commit SHA, timestamp
          printf '{\n  "commit": "%s",\n  "version": "%s",\n  "generated_at": "%s",\n  "git_version": "%s"\n}\n' \
            "$(git rev-parse HEAD)" "$version" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(git --version | awk '{print $3}')" \
            > "$out/manifest.json"

      - name: Commit release snapshot
        run: |
          set -euo pipefail
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add .llm/evidence/releases/
          if ! git diff --cached --quiet; then
            git commit -m "chore(evidence): add release snapshot for $(git describe --tags --always)"
            git push
          else
            echo "No snapshot changes to commit"
          fi
EOF

    print_success "Created .github/workflows/release-snapshot.yml"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Bootstrap Complete!                                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Created:${NC}"
print_info "✓ AI memory structure (AGENTS.md, docs/)"
print_info "✓ Git hooks (.githooks/)"
print_info "✓ Tech decisions (.tech-decisions.yml)"
print_info "✓ CI configuration (.github/workflows/)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  ${NC}1. Review and customize:${NC}"
print_info "     • docs/constraints.md - Add project-specific rules"
print_info "     • .tech-decisions.yml - Fill in your tech choices"
print_info "     • AGENTS.md - Review AI guidelines"
echo ""
echo -e "  ${NC}2. Create your first ADR:${NC}"
print_info "     • Copy docs/adr/ADR_TEMPLATE.md"
print_info "     • Name it ADR-0001-your-decision.md"
echo ""
echo -e "  ${NC}3. Commit the framework:${NC}"
print_info "     git add ."
print_info "     git commit -m 'Add AI-assisted development framework'"
echo ""
echo -e "${CYAN}For help: See ai-assisted-development-framework.md${NC}"
echo ""
