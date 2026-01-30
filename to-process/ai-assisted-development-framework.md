# AI-Assisted Development Framework

A comprehensive system for maintaining code quality, security, and consistency when using AI for development.

## 📦 What's Included

This package contains everything you need to set up an AI-friendly development workflow with automated quality controls:

### Documentation
- **`ai-assisted-development-framework.md`** - Complete guide with detailed explanations of all components
- **`quick-reference.md`** - One-page reference for daily use
- **`commit-hooks-for-ai.md`** - Your original notes on hook strategy (included for reference)
- **`create-llm-memory.ps1`** - Your original memory creation script (included for reference)

### Setup Scripts
- **`bootstrap-ai-repo.ps1`** - Windows PowerShell bootstrap script
- **`bootstrap-ai-repo.sh`** - Linux/Mac bash bootstrap script

## 🎯 What Problem Does This Solve?

When using AI to write code, you want to:
1. **Maintain quality** - Ensure AI follows best practices
2. **Preserve consistency** - Keep architectural decisions coherent
3. **Catch mistakes early** - Fast feedback loops
4. **Document decisions** - So AI (and humans) understand context

This framework provides:
- **AI Memory** - Structured docs AI agents can read to understand your project
- **Fast Feedback** - Pre-commit hooks catch obvious issues in seconds
- **Authoritative Validation** - CI enforces comprehensive quality standards
- **Progressive Enhancement** - Starts simple, grows with complexity

## 🚀 Quick Start

### For New Projects

```bash
# 1. Create your git repo
git init
cd your-repo

# 2. Copy bootstrap script to your repo
#    (bootstrap-ai-repo.ps1 for Windows, bootstrap-ai-repo.sh for Linux/Mac)

# 3. Run bootstrap
.\scripts\bootstrap-ai-repo.ps1   # Windows
./scripts/bootstrap-ai-repo.sh     # Linux/Mac

# 4. Customize generated files
#    - docs/constraints.md
#    - .tech-decisions.yml
#    - docs/standards/*.md

# 5. Create your first ADR
cp docs/adr/ADR_TEMPLATE.md docs/adr/ADR-0001-initial-setup.md
# Edit the file...

# 6. Commit the framework
git add .
git commit -m "Add AI-assisted development framework"
```

### For Existing Projects

```bash
# 1. Place bootstrap script in scripts/ directory
mkdir -p scripts
# Copy bootstrap-ai-repo.ps1 or bootstrap-ai-repo.sh here

# 2. Run bootstrap (add --force to overwrite existing files)
.\scripts\bootstrap-ai-repo.ps1 -Force   # Windows
./scripts/bootstrap-ai-repo.sh --force   # Linux/Mac

# 3. Review generated files and customize
# 4. Migrate any existing documentation into the new structure
# 5. Commit changes
```

## 📖 What Gets Created

The bootstrap script creates this structure:

```
your-repo/
├── AGENTS.md                      # Entry point for AI agents
├── .tech-decisions.yml            # Machine-readable tech stack
├── .githooks/                     # Version-controlled git hooks
│   ├── pre-commit                 # Fast quality checks
│   └── commit-msg                 # Commit message validation
├── docs/
│   ├── constraints.md             # Quick index of rules
│   ├── catalog.md                 # Reusable components
│   ├── adr/                       # Architecture Decision Records
│   │   ├── README.md
│   │   └── ADR_TEMPLATE.md
│   └── standards/                 # Coding standards
│       ├── README.md
│       └── code.md
└── .github/workflows/
    └── quality.yml                # CI quality checks
```

## 🔄 How It Works

### The Three Layers

```
┌─────────────────────────────────────────────────────┐
│ 1. AI Memory (Knowledge Layer)                      │
│    What to build and how to build it                │
│    Location: AGENTS.md, docs/*                      │
├─────────────────────────────────────────────────────┤
│ 2. Pre-Commit Hooks (Fast Feedback)                 │
│    Catch obvious mistakes before commit             │
│    Location: .githooks/*                            │
│    Speed: < 10 seconds                              │
├─────────────────────────────────────────────────────┤
│ 3. CI Pipeline (Authoritative Validation)           │
│    Comprehensive quality enforcement                │
│    Location: .github/workflows/*                    │
│    Speed: < 15 minutes                              │
└─────────────────────────────────────────────────────┘
```

### Workflow Example

```
Developer/AI makes changes
    ↓
Pre-commit hook runs
    ├─ Format check ✓
    ├─ Quick lint ✓
    └─ Secrets scan ✓
    ↓
Commit message validated
    ├─ Not too vague ✓
    ├─ Adequate length ✓
    └─ ADR reference (if needed) ✓
    ↓
Commit created
    ↓
Push to remote
    ↓
CI pipeline runs
    ├─ All hook checks (enforced)
    ├─ Full test suite + coverage
    ├─ Integration tests
    ├─ Security scans
    └─ Architecture validation
    ↓
Merge ✓
```

## 📋 Key Features

### For AI Agents
- **Structured documentation** - Easy to parse and understand
- **Clear entry points** - AGENTS.md tells AI what to read
- **Decision records** - Context for why things are the way they are
- **Reusable components** - Catalog prevents reinventing wheels
- **Machine-readable standards** - .tech-decisions.yml for automated validation

### For Developers
- **Fast feedback** - Catch issues in seconds, not minutes
- **Consistent quality** - Standards applied automatically
- **Clear guidelines** - Know what's expected
- **Documented decisions** - Understand the "why"
- **Gradual adoption** - Start simple, add complexity as needed

### For Teams
- **Shared understanding** - Decisions documented in ADRs
- **Knowledge preservation** - Constraints.md captures lessons learned
- **Onboarding aid** - New members read AGENTS.md
- **Quality metrics** - Coverage, mutation scores tracked
- **Continuous improvement** - Framework evolves with project

## 🎓 Learning Path

**Day 1:** Quick Start
- Run bootstrap script
- Read quick-reference.md
- Make a test commit to see hooks in action

**Week 1:** Customization
- Fill in .tech-decisions.yml with your choices
- Add project-specific rules to docs/constraints.md
- Create first ADR for a real decision

**Month 1:** Integration
- Update docs/catalog.md as components stabilize
- Add language-specific standards
- Tune CI pipeline for your needs

**Ongoing:** Evolution
- Review constraints quarterly
- Update ADRs when decisions change
- Add checks based on real issues found

## 🔧 Customization

### Adjust Coverage Requirements
Edit `.tech-decisions.yml`:
```yaml
testing:
  unit_coverage_minimum: 80  # Change to your standard
  mutation_score_minimum: 70
```

### Add Language-Specific Checks
Edit `.githooks/pre-commit`:
```bash
# Add your language check
if [ -f "build.gradle" ]; then
    echo "  • Java: Running checks..."
    ./gradlew check
fi
```

### Modify Commit Message Rules
Edit `.githooks/commit-msg`:
```bash
# Add your team's conventions
if ! echo "$commit_msg" | grep -qE '^(feat|fix|docs|style|refactor|test|chore):'; then
    echo "  ✗ Must start with conventional commit prefix"
    FAILED=1
fi
```

## 🤝 Integration with Your Tools

### IDE Integration
Most IDEs can run git hooks automatically. Configure your IDE to:
- Run pre-commit checks on save
- Validate commit messages before commit
- Show coverage inline

### CI/CD Integration
The framework works with:
- GitHub Actions (included)
- GitLab CI (adapt quality.yml)
- Jenkins (convert to Jenkinsfile)
- CircleCI (convert to config.yml)

### AI Tools Integration
Works with:
- Claude Code
- GitHub Copilot
- Cursor
- Any AI coding assistant

Just point the AI to read `AGENTS.md` before making changes.

## 📚 Documentation Guide

### ai-assisted-development-framework.md
**Complete reference** - Read this to understand:
- Full system architecture
- How each component works
- Implementation details
- Language-specific configurations
- Maintenance procedures

### quick-reference.md
**Daily use** - Keep this handy for:
- Quick task lookup
- Troubleshooting
- Common commands
- File locations
- Best practices

### AGENTS.md (generated)
**AI entry point** - Tells AI agents:
- What to read before changes
- When to consult ADRs
- Contribution expectations
- Required citations

## 🔍 Examples

### Creating an ADR
```bash
# Scenario: Choosing between PostgreSQL and MongoDB

# 1. Copy template
cp docs/adr/ADR_TEMPLATE.md docs/adr/ADR-0001-database-choice.md

# 2. Fill in:
#    Context: Need persistent storage, relational data, ACID guarantees
#    Decision: Use PostgreSQL
#    Consequences: Strong consistency, familiar SQL, excellent tooling
#    Alternatives: MongoDB (too flexible), MySQL (licensing concerns)

# 3. Reference in code
# src/db.rs: "Using PostgreSQL (see ADR-0001)"

# 4. Add constraint
# docs/constraints.md:
#   - **Use PostgreSQL for all data storage**
#     Never use: MongoDB, MySQL
#     Source: docs/adr/ADR-0001-database-choice.md
```

### Adding to Catalog
```bash
# Scenario: Created reusable retry logic

# Edit docs/catalog.md:
## Common building blocks

- **`src/utils/retry.rs`** — Exponential backoff retry logic
  Use when: Making network requests that may fail transiently
  Key entry points: `retry_with_policy()`, `RetryPolicy::default()`
  Notes: Max 5 retries by default. Configure via `RetryConfig`.
        Does not retry on 4xx errors (client errors are not transient).
```

## 🆘 Support

### If Hooks Aren't Running
```bash
# Check configuration
git config core.hooksPath
# Should show: .githooks

# Fix if needed
git config core.hooksPath .githooks
chmod +x .githooks/*  # Linux/Mac only
```

### If CI Fails But Local Passes
```bash
# Run full local validation
./scripts/validate-local.sh  # (create this script to mirror CI)

# Common causes:
# - Coverage too low (check test coverage report)
# - Integration tests failing (run cargo test --test '*')
# - Security vulns (run cargo audit)
```

### If AI Ignores Constraints
1. Verify constraint is in `AGENTS.md` mandatory triggers
2. Add to `.tech-decisions.yml` for machine validation
3. Add CI check to enforce automatically
4. Make error messages actionable

## 🎯 Success Metrics

Track these to measure framework effectiveness:

### Quality Metrics
- Test coverage trend (should stay > 80%)
- Mutation score (should improve over time)
- Pre-commit catch rate (issues found before CI)
- ADR coverage (% of decisions documented)

### Velocity Metrics
- Time to onboard new developers
- Frequency of "how do we do X?" questions
- Time spent in code review
- CI feedback time

### Health Metrics
- Hook bypass rate (should be < 5%)
- Constraint violation rate in PRs
- ADR reference rate in architectural commits
- Standards update frequency

## 🔮 What's Next?

After setup, consider:

1. **Tool Integration**
   - Add IDE plugins for pre-commit
   - Set up coverage dashboards
   - Configure security scanning

2. **Process Refinement**
   - Weekly ADR review meetings
   - Monthly constraint review
   - Quarterly framework retrospective

3. **Advanced Features**
   - Mutation testing in CI
   - Architecture compliance checks
   - Automatic changelog generation
   - Release automation

## 📄 License

Adapt this framework to your needs. No attribution required.

## 🙏 Acknowledgments

Integrates ideas from:
- Your original `commit-hooks-for-ai.md` strategy
- Your `create-llm-memory.ps1` approach
- ADR methodology
- Pre-commit framework philosophy
- Clean Architecture principles

---

**Ready to start?** Run the bootstrap script and you'll have quality controls for AI-assisted development in minutes.

Questions? Check `quick-reference.md` for common tasks and troubleshooting.
