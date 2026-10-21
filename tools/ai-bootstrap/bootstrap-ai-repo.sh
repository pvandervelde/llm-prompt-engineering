#!/bin/bash
# Bootstrap AI-assisted development framework for a repository
# Usage: ./bootstrap-ai-repo.sh [--force]

set -e

# Parse arguments
FORCE=0
if [[ "$1" == "--force" ]]; then
    FORCE=1
fi

# Get script directory (for locating sibling framework files to copy FROM, e.g.
# tools/workflow/lib, workflow/pipelines.yml) and repo root. This script may be
# installed globally (e.g. a user's Claude
# agent tools directory) and invoked against any repo as the current working
# directory, so the repo root must come from git, never from where this
# script itself happens to live.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
# Two levels up from tools/ai-bootstrap/ -- this framework's own repo root,
# used only to locate sibling source files (tools/workflow/,
# workflow/pipelines.yml) to copy FROM. Never used as the destination: every
# write below still goes through $ROOT, resolved via git from the current
# working directory per the rule above.
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
if [ -z "$ROOT" ]; then
    print_error "Not in a git repository. Initialize git first: git init"
    exit 1
fi

# ============================================================================
# Step 1: Create AI Memory Structure
# ============================================================================
print_step "[1/7] Creating AI memory structure..."

# Create minimal structure
mkdir -p "$ROOT/docs/adr"
mkdir -p "$ROOT/docs/standards"
mkdir -p "$ROOT/.githooks"

print_success "Minimal directory structure created"

# ============================================================================
# Step 2: Create Git Hooks
# ============================================================================
print_step "[2/7] Creating git hooks..."

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
print_step "[3/7] Detecting tech stack..."

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
print_step "[4/7] Creating .tech-decisions.yml..."

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
# capability terms (test, mutation, fuzz, formal, ...); the Conductor resolves
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

# Maps module paths to the criticality classes used by mutation_targets above
# and by the QA Engineer agent's Criticality Tiers table. Glob-matched against
# the paths touched by a task; first match wins. Customize for your project -
# an empty or missing mapping means every module defaults to domain_logic.
criticality:
  safety_critical: []  # e.g. ["src/safety/**", "src/control/**"]
  parser: []            # e.g. ["src/protocol/**"]
  domain_logic: []      # e.g. ["src/domain/**"]
  api_boundary: []      # e.g. ["src/api/**"]
  adapter: []           # e.g. ["src/infra/**"]

# Maps task-referenced paths to a domain for \`workflow classify\` (replaces
# the hand-written Frontend/Backend/Infrastructure prose tables in
# tech-lead.md Step 2 and planner.md's old Project Type Detection section).
# A path matching zero or more-than-one domain's globs is "ambiguous" --
# classify asks the human once in that case, same as the prose it replaces.
classify:
  frontend: ["docs/spec/components/**", "docs/spec/ui/**", "src/components/**", "src/ui/**"]
  backend: ["docs/spec/interfaces/**", "src/**"]
  infrastructure: ["docs/spec/infrastructure/**", "docs/spec/modules/**", "infra/**"]

# A diff touching any of these paths is always \`elevated\` -- never
# \`minimal\` or \`standard\`, regardless of diff size or test coverage, and
# a human cannot override it down. Used by \`workflow tier\`.
# e.g. risk_paths: ["src/auth/**", "src/safety/**", "**/secrets/**"]
risk_paths: []

# Per-task sandboxing for the phases that execute this repo's own toolchain
# (RED/GREEN/REFACTOR/AUDIT, infra IMPLEMENT -- see workflow/isolation.md,
# shipped as \`container\` by default for those phases in pipelines.yml).
# \`mechanism\` picks the container runtime (podman preferred, falls back to
# docker if omitted). \`overrides\` opts individual phases OUT of the
# container-by-default policy for this repo -- a single task cannot opt
# below what this file says (see \`workflow isolation --override\`'s
# asymmetric refusal); only an edit here can. \`network.allow\` extends the
# toolchain-derived egress allowlist (e.g. a private registry mirror).
isolation:
  mechanism: podman  # podman (preferred) or docker; auto-detected if omitted
  overrides: {}       # add phase lines indented under this key to override,
                        # e.g. replace {} with:
                        #   overrides:
                        #     RED: direct
  network:
    allow: []          # extra egress allowlist entries beyond toolchain defaults

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
# Step 5: Distribute Workflow Engine
# ============================================================================
print_step "[5/7] Installing the workflow engine (tools/workflow/, workflow/pipelines.yml)..."

# The engine resolves workflow/pipelines.yml and every path it writes
# relative to the TARGET repo's own git root (never relative to its own
# script path -- see tools/workflow/README.md), so both the engine scripts
# and the schema they read must actually live inside the target repo. They
# are copied from THIS framework's own checkout (via $FRAMEWORK_ROOT, a
# sibling-file lookup -- not the target-repo-resolution rule above) rather
# than installed globally, for the same reason .tech-decisions.yml and
# AGENTS.md are seeded per-repo instead of shared: a repo may reasonably
# customize workflow/pipelines.yml (an extra gate, a renamed phase) once
# bootstrapped, same as it customizes .tech-decisions.yml.

# copy_workflow_file <relative-path> [executable]
# $2 = "x" makes the destination executable (shell scripts only). Refuses a
# symlinked source (security -- see install.sh's reject_symlink for the
# full rationale: a symlink planted in tools/workflow/ could otherwise be
# used to copy arbitrary content this user can read into the target repo).
copy_workflow_file() {
    local rel="$1" mode="${2:-}"
    local src="$FRAMEWORK_ROOT/$rel" dst="$ROOT/$rel"

    if [ -L "$src" ]; then
        print_error "Refusing to follow symlink (security): $src"
        return 0
    fi
    [ -f "$src" ] || return 0

    if [ -f "$dst" ] && [ $FORCE -eq 0 ]; then
        print_warning "$rel already exists (use --force to overwrite)"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    if [ "$mode" = "x" ]; then
        chmod +x "$dst"
    fi
    print_success "Copied $rel"
}

copy_workflow_file "tools/workflow/workflow.sh" x
copy_workflow_file "tools/workflow/workflow.ps1"
copy_workflow_file "tools/workflow/migrate-assertions.sh" x
copy_workflow_file "tools/workflow/migrate-assertions.ps1"

if [ -L "$FRAMEWORK_ROOT/tools/workflow/lib" ]; then
    print_error "Refusing to follow symlink (security): $FRAMEWORK_ROOT/tools/workflow/lib"
elif [ -d "$FRAMEWORK_ROOT/tools/workflow/lib" ]; then
    for lib_file in "$FRAMEWORK_ROOT"/tools/workflow/lib/*; do
        [ -f "$lib_file" ] || [ -L "$lib_file" ] || continue
        copy_workflow_file "tools/workflow/lib/$(basename "$lib_file")"
    done
fi

copy_workflow_file "workflow/pipelines.yml"

# ============================================================================
# Step 6: Setup Beads (Optional Task Tracking)
# ============================================================================
print_step "[6/7] Setting up Beads task tracking (optional)..."

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
    print_info "In the meantime, agents will use ./.llm/tasks.md for task tracking."
fi

# ============================================================================
# Step 7: Initialize Fallback Task Structure
# ============================================================================
print_step "[7/7] Initializing fallback task structure (.llm/tasks.md)..."

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
> If Beads is installed and initialized, tasks can be synced to JSON using the
> task-export tool provided by the agent framework.

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
echo -e "${CYAN}For help: See tools/ai-bootstrap/README.md${NC}"
echo ""
