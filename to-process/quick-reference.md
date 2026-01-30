# AI Development Framework - Quick Reference

A one-page reference for using the AI-assisted development framework.

## 🚀 Quick Start

**First time setup:**
```bash
# Windows
.\scripts\bootstrap-ai-repo.ps1

# Linux/Mac
./scripts/bootstrap-ai-repo.sh
```

**Add to existing repo:**
```bash
# 1. Copy framework files to your repo
# 2. Run bootstrap script
# 3. Customize docs/constraints.md and .tech-decisions.yml
# 4. Commit
```

---

## 📁 Key Files

| File | Purpose | Update When |
|------|---------|-------------|
| `AGENTS.md` | Entry point for AI agents | Never (unless changing structure) |
| `docs/constraints.md` | Quick index of hard rules | Found a common mistake |
| `docs/catalog.md` | Reusable components | New standard component added |
| `docs/adr/*.md` | Architecture decisions | Making architectural choice |
| `docs/standards/*.md` | Coding standards | Adopting new convention |
| `.tech-decisions.yml` | Machine-readable tech stack | Tech stack changes |
| `.githooks/*` | Pre-commit checks | Adding new validation |
| `.github/workflows/*.yml` | CI pipeline | Adding new checks |

---

## 🤖 For AI Agents

**Before making changes, always:**

1. Read `AGENTS.md`
2. Read `docs/constraints.md`
3. Check `docs/catalog.md` for existing solutions
4. Search `docs/adr/` if touching:
   - Architecture boundaries
   - Public APIs
   - Database schemas
   - Security/auth
   - Infrastructure

**When committing:**
- Reference ADRs for architectural changes
- Follow constraints from `.tech-decisions.yml`
- Explain "why" in commit message
- Don't bypass hooks (unless documented exception)

---

## ✅ Automated Checks

### Pre-Commit (Fast)
Runs automatically before each commit:
- ✓ Secrets detection
- ✓ Format check
- ✓ Quick linting
- ✓ Large file detection
- ✓ Merge conflict markers

**Bypass:** `git commit --no-verify` (not recommended)

### Commit Message
Validates commit message:
- ✓ Minimum length
- ✓ Not too vague
- ⚠ ADR reference for infrastructure changes
- ℹ Suggests adding "why" for single-line commits

### CI Pipeline (Comprehensive)
Runs on push/PR:
- ✓ All pre-commit checks (enforced)
- ✓ Full test suite + coverage
- ✓ Integration tests
- ✓ Security scans
- ✓ Mutation testing
- ✓ Architecture compliance

---

## 📝 Creating an ADR

```bash
# 1. Copy template
cp docs/adr/ADR_TEMPLATE.md docs/adr/ADR-0001-my-decision.md

# 2. Fill in sections
#    - Context: What problem?
#    - Decision: What did we choose?
#    - Consequences: What does this enable/forbid?
#    - Alternatives: What else did we consider?

# 3. Reference in code/commits
#    "See ADR-0001 for rationale"

# 4. Update docs/constraints.md if it creates a new rule
```

**ADR numbering:**
- Use sequential numbers: ADR-0001, ADR-0002, etc.
- Don't reuse numbers
- Mark superseded ADRs as "Status: Superseded by ADR-XXXX"

---

## 🔧 Common Tasks

### Add a new standard
```bash
# 1. Create/update docs/standards/TOPIC.md
# 2. Reference in docs/constraints.md if it's a hard rule
# 3. Update .tech-decisions.yml if machine-checkable
# 4. Add CI check if automated validation possible
```

### Add a reusable component
```bash
# 1. Build and test the component
# 2. Add entry to docs/catalog.md
# 3. Include: path, purpose, usage, gotchas
```

### Update tech stack
```bash
# 1. Document decision in ADR
# 2. Update .tech-decisions.yml
# 3. Update language-specific docs/standards/*.md
# 4. Update CI configuration for new tooling
# 5. Update pre-commit hooks if applicable
```

### Run all checks locally
```bash
# Before pushing, validate everything:
./scripts/validate-local.sh   # Linux/Mac
.\scripts\validate-local.ps1  # Windows

# This runs same checks as CI
```

---

## 🚨 Troubleshooting

### Hooks not running
```bash
# Check hook configuration
git config core.hooksPath

# Should output: .githooks

# If not, run:
git config core.hooksPath .githooks

# Make hooks executable (Linux/Mac)
chmod +x .githooks/*
```

### Pre-commit failing
```bash
# See what failed and fix it
# Common issues:
#   - Code not formatted: cargo fmt / prettier --write .
#   - Lint errors: Fix the warnings
#   - Large files: Use Git LFS or exclude

# Emergency bypass (discouraged):
git commit --no-verify
# Note: CI will still enforce these checks
```

### CI failing but local passed
```bash
# CI is more comprehensive than pre-commit
# Run full local validation:
./scripts/validate-local.sh

# Common causes:
#   - Test coverage too low
#   - Integration tests failing
#   - Security vulnerabilities in dependencies
```

### Can't find right ADR
```bash
# Search ADRs by keyword
grep -r "keyword" docs/adr/

# Or check docs/constraints.md for links

# Keywords to try:
#   - Technical domain (auth, api, database)
#   - Component name
#   - Technology (postgres, rust, kubernetes)
```

---

## 📊 Metrics and Health

### Coverage Requirements
- **Unit tests:** 80% minimum (configurable in `.tech-decisions.yml`)
- **Mutation score:** 70% minimum
- Check in CI output or coverage reports

### Quality Thresholds
All configurable in `.tech-decisions.yml`:
- Max function length: 50 lines
- Max file length: 500 lines
- Max complexity: 10
- No duplicate blocks

### Security Scanning
- Dependency vulnerabilities: Fail on HIGH or CRITICAL
- Secrets: Always fail if detected
- Code scanning: CodeQL or equivalent

---

## 🎯 Best Practices

### For Developers
1. **Read before writing** — Check catalog and standards first
2. **Small commits** — Easier to review and revert
3. **Meaningful messages** — Future you will thank you
4. **Don't bypass hooks** — They catch real issues
5. **Update docs** — Keep memory fresh

### For AI Agents
1. **Always read AGENTS.md first** — Saves back-and-forth
2. **Reference constraints** — Show which rules apply
3. **Cite ADRs** — Explain why this approach
4. **Use catalog** — Don't reinvent existing components
5. **Explain trade-offs** — Help humans understand choices

### For Teams
1. **Review ADRs regularly** — Retire obsolete ones
2. **Keep constraints.md short** — 10-30 items max
3. **Update catalog promptly** — As soon as component stabilizes
4. **Evolve standards gradually** — Big changes need ADRs
5. **Monitor check effectiveness** — Are they catching issues?

---

## 🔗 Quick Links

- **Full Guide:** `ai-assisted-development-framework.md`
- **AI Entry Point:** `AGENTS.md`
- **Tech Stack:** `.tech-decisions.yml`
- **Constraints:** `docs/constraints.md`
- **Reusables:** `docs/catalog.md`
- **Decisions:** `docs/adr/`
- **Standards:** `docs/standards/`

---

## 💡 Tips

**Speeding up pre-commit:**
- Pre-commit runs fast checks only (< 10s)
- If slower, move checks to CI
- Use `--no-verify` sparingly

**Making checks useful:**
- Check failure = actionable message
- Include "how to fix" in error output
- Link to relevant docs

**Keeping docs current:**
- Review monthly: Are constraints still relevant?
- Review quarterly: Update .tech-decisions.yml
- Review on incidents: What could have prevented this?

**Evolving the framework:**
```bash
# AI can help improve the framework itself:
# "Review recent failed builds and suggest new checks"
# "Our pre-commit is slow, which checks can move to CI?"
# "Analyze recent commits - what patterns should be in catalog?"
```

---

## 🆘 Getting Help

1. Check this reference
2. Read full guide: `ai-assisted-development-framework.md`
3. Search ADRs for similar decisions
4. Ask team: "Anyone solved X before?"
5. Create ADR for new patterns

**Common Questions:**

**Q: When should I create an ADR?**
A: For decisions that affect multiple features or developers. Code-level decisions usually don't need ADRs.

**Q: Can I bypass hooks?**
A: Yes with `--no-verify`, but CI will still enforce. Only bypass for documented exceptions.

**Q: How often should I update constraints.md?**
A: When you catch yourself explaining the same rule twice. Keep it short.

**Q: What if AI ignores constraints?**
A: 1) Check if constraint is in AGENTS.md triggers, 2) Make it machine-checkable in .tech-decisions.yml, 3) Add CI check

**Q: How do I deprecate an ADR?**
A: Update status to "Superseded by ADR-XXXX" and create new ADR with updated decision.

---

**Remember:** This framework helps maintain quality while using AI for development. It's a living system — evolve it as you learn what works for your team.
