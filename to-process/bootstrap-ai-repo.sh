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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

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
    
    cat > "$TECH_FILE" << EOF
# Technology Decisions and Standards
# Generated: $(date +%Y-%m-%d)
# This file is read by CI and commit hooks to enforce standards

# Detected languages
languages: [$LANGS_STR]

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
# Step 5: Create CI Configuration
# ============================================================================
print_step "[5/5] Creating CI configuration..."

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
