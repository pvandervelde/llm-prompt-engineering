# Codebase Catalog

An automatically maintained index of public symbols across the codebase.
Structured by domain so agents and developers can find existing abstractions
before writing new ones.

---

## How it works

1. **`scripts/update_catalog.py`** walks the repo with `ast-grep`, extracting every public function, type, struct, trait, and interface.
2. New symbols are sent to the Anthropic API in batches for description generation. Existing entries are left untouched.
3. Per-domain markdown files are written to `docs/catalog/<domain>.md`, plus a master index at `docs/catalog/index.md`.
4. A state file (`.codeindex/.catalog-state.json`) tracks the last-indexed commit so incremental runs are fast.

The `.githooks/post-commit` hook runs `--incremental` automatically after every commit.

---

## Prerequisites

**Python packages:**
```sh
pip install -r scripts/requirements-catalog.txt
```

**ast-grep** (AST-aware code search):
```sh
cargo install ast-grep
```
Or download a binary from [ast-grep.github.io](https://ast-grep.github.io/guide/quick-start.html).

**Anthropic API key** (for description generation):
```sh
# Add to your shell profile or .env
export ANTHROPIC_API_KEY=sk-ant-...
```
Without a key the script runs but writes placeholder descriptions. You can generate descriptions later by running a full re-index once the key is set.

---

## First-time setup

```sh
# 1. Install dependencies
pip install -r scripts/requirements-catalog.txt

# 2. Run a full index (takes a minute on large repos)
python scripts/update_catalog.py

# 3. Commit the generated catalog
git add docs/catalog/
git commit -m "docs(catalog): initial catalog generation"
```

The git hook is already wired in if your repo uses `.githooks/` with `core.hooksPath`. Verify with:
```sh
git config core.hooksPath
# should print: .githooks
```

---

## Commands

| Command | What it does |
|---------|-------------|
| `python scripts/update_catalog.py` | Full re-index of the entire repo |
| `python scripts/update_catalog.py --incremental` | Changed files only (fast; used by the git hook) |
| `python scripts/update_catalog.py --dry-run` | Preview new/removed entries without writing |
| `python scripts/update_catalog.py --domain auth` | Re-index a single domain only |
| `python scripts/update_catalog.py --config path/to/other.yml` | Use a different config file |

---

## Output structure

```
docs/catalog/
├── index.md          Master index — all entries sorted by domain
├── auth.md           Authentication and authorisation symbols
├── core.md           Shared types and utilities
├── api.md            HTTP boundary symbols
├── can-protocol.md   CAN FD frame parsing
└── ...               One file per domain in catalog.config.yml
```

Each file contains a markdown table:

| Name | Kind | Location | Description | Tags |
|------|------|----------|-------------|------|
| `validate_hmac_signature` | fn | `` `api_gateway/auth.rs:42` `` | Validates HMAC-SHA256 signature against request body using pre-shared key | auth, validation |

---

## Configuration

Edit `catalog.config.yml` in the repo root.

**Key sections:**

- **`domains`** — Maps directory glob patterns to domain names. First match wins; the last entry should be a `**` catch-all. Add your own domains here.
- **`languages`** — ast-grep patterns per language. Each pattern must include `$NAME`. Add new languages by following the existing entries.
- **`exclude_global`** — Paths excluded regardless of language (build artifacts, vendored deps, etc.).
- **`llm.model`** — Defaults to `claude-haiku-4-5-20251001` (fast, cheap). Switch to `claude-sonnet-4-6` for better descriptions.

**Adding a domain:**
```yaml
domains:
  - name: telemetry
    description: "Metrics, tracing, and observability"
    paths:
      - "**/telemetry/**"
      - "**/metrics/**"
      - "**/tracing/**"
    tags: [observability]
```

**Adding a language:**
```yaml
languages:
  go:
    extensions: [".go"]
    exclude_patterns: ["**/*_test.go"]
    symbols:
      - kind: fn
        pattern: "func $NAME($$$)"
        tags: []
```

---

## How agents use the catalog

Agents consult `docs/catalog/index.md` (or a specific domain file) before implementing anything. The lookup is a text search on the Name and Tags columns.

**In agent prompts:**
```
Before implementing any new abstraction, search docs/catalog/index.md for
entries with similar names or matching tags. If a catalog entry covers your
need, use it rather than creating a new one.
```

**Example workflow:**
- Coder about to write a HMAC validation function
- Searches catalog for `hmac` or `validation`  
- Finds `validate_hmac_signature` in `api_gateway/auth.rs`
- Reuses it instead of writing a duplicate

---

## Incremental mode details

The script stores the last-indexed commit hash in `.codeindex/.catalog-state.json`. On `--incremental` runs it computes `git diff --name-only <last-commit> HEAD` to determine which files changed, then only re-scans those files. Deleted files have their catalog entries pruned.

If the stored commit no longer exists (e.g. after a rebase), the script falls back to a full re-index automatically.

**`.codeindex/` should be in `.gitignore`** — it is machine-local state and not shared:
```gitignore
.codeindex/
```

The `docs/catalog/` output **should be committed** — it is the artifact that agents and developers read.

---

## Skipping the hook for one commit

```sh
git commit --no-verify
```

The hook never blocks a commit — catalog failures exit 0 with a warning.

---

## Troubleshooting

**"ast-grep not found on PATH"**  
Install it: `cargo install ast-grep` and ensure `~/.cargo/bin` is on your PATH.

**Descriptions show "description unavailable"**  
`ANTHROPIC_API_KEY` is not set or the API returned an error. Set the key and run a full re-index: `python scripts/update_catalog.py`.

**"No changes since last run" but files clearly changed**  
The state file tracks the commit hash, not wall time. If you edited files without committing, run without `--incremental`: `python scripts/update_catalog.py`.

**A symbol is missing from the catalog**  
The ast-grep pattern for its language may not match it. Check `catalog.config.yml` → `languages` → `symbols`. Use `ast-grep run --pattern "your pattern" --lang rust path/to/file.rs` to test patterns interactively.
