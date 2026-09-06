#!/usr/bin/env python3
"""
update_catalog.py — Deterministic codebase catalog generator.

Walks the repository using ast-grep to extract public symbols, generates
descriptions via the Anthropic API for new entries only, and writes
per-domain markdown catalog files to docs/catalog/.

Discovery (ast-grep) is exhaustive and deterministic.
The LLM is only invoked for description generation on new/changed symbols.

Usage:
    python scripts/update_catalog.py                  Full re-index
    python scripts/update_catalog.py --incremental    Changed files only (fast)
    python scripts/update_catalog.py --dry-run        Preview without writing
    python scripts/update_catalog.py --domain auth    Single domain only

Requirements:
    pip install anthropic pyyaml
    cargo install ast-grep   (or install from https://ast-grep.github.io)

Environment:
    ANTHROPIC_API_KEY   Required for description generation.
                        Without it, symbols are indexed with placeholder descriptions.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from fnmatch import fnmatch
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ── Dependency checks ──────────────────────────────────────────────────────────

try:
    import yaml
except ImportError:
    print("Error: 'pyyaml' package not found.", file=sys.stderr)
    print("  pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# ── Data models ───────────────────────────────────────────────────────────────

@dataclass
class Symbol:
    """A public symbol extracted from source code by ast-grep."""
    name: str
    kind: str           # fn, struct, enum, trait, type, class, interface
    file: str           # Relative to repo root, always forward slashes
    line: int           # 1-indexed
    signature: str      # Truncated to first meaningful line(s)
    language: str
    domain: str
    tags: List[str]
    description: str = ""  # Filled in by generate_descriptions()

    @property
    def key(self) -> str:
        """Stable dedup key. Includes line to distinguish same-named symbols in one file."""
        return f"{self.file}::{self.name}::{self.line}"

    @property
    def location(self) -> str:
        return f"`{self.file}:{self.line}`"


@dataclass
class CatalogEntry:
    """A single row in the catalog table."""
    key: str
    name: str
    kind: str
    file: str
    line: int
    description: str
    tags: List[str]
    domain: str

    @property
    def location(self) -> str:
        return f"`{self.file}:{self.line}`"


# ── Config loading ─────────────────────────────────────────────────────────────

def load_config(config_path: str) -> dict:
    path = Path(config_path)
    if not path.exists():
        print(f"Error: Config file not found: {config_path}", file=sys.stderr)
        print("Expected catalog.config.yml in the repo root.", file=sys.stderr)
        sys.exit(1)

    with open(path, encoding="utf-8") as f:
        config = yaml.safe_load(f)

    for required_key in ("catalog", "languages", "domains"):
        if required_key not in config:
            print(f"Error: catalog.config.yml missing required key '{required_key}'", file=sys.stderr)
            sys.exit(1)

    return config


# ── Repository utilities ───────────────────────────────────────────────────────

def find_repo_root() -> Path:
    """Walk up from cwd to find the git repository root."""
    for parent in [Path.cwd()] + list(Path.cwd().parents):
        if (parent / ".git").exists():
            return parent
    print("Error: Not inside a git repository.", file=sys.stderr)
    sys.exit(1)


def get_current_commit(repo_root: Path) -> Optional[str]:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=repo_root, capture_output=True, text=True, timeout=30,
        )
    except subprocess.TimeoutExpired:
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def get_changed_files(repo_root: Path, last_commit: str) -> Optional[List[str]]:
    """
    Files changed between last_commit and HEAD.
    Returns None if the diff cannot be computed (triggers full re-index).
    """
    # Verify the stored commit still exists (rebase safety)
    try:
        verify = subprocess.run(
            ["git", "cat-file", "-e", last_commit],
            cwd=repo_root, capture_output=True, timeout=30,
        )
    except subprocess.TimeoutExpired:
        print("Warning: git cat-file timed out — full re-index.")
        return None
    if verify.returncode != 0:
        print(f"Warning: Stored commit {last_commit[:8]} no longer exists — full re-index.")
        return None

    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", last_commit, "HEAD"],
            cwd=repo_root, capture_output=True, text=True, timeout=30,
        )
    except subprocess.TimeoutExpired:
        print("Warning: git diff timed out — full re-index.")
        return None
    if result.returncode != 0:
        print("Warning: git diff failed — full re-index.")
        return None

    return [f.strip() for f in result.stdout.splitlines() if f.strip()]


def get_deleted_files(repo_root: Path, last_commit: str) -> List[str]:
    """Files deleted between last_commit and HEAD."""
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=D", last_commit, "HEAD"],
            cwd=repo_root, capture_output=True, text=True, timeout=30,
        )
    except subprocess.TimeoutExpired:
        return []
    if result.returncode != 0:
        return []
    return [f.strip() for f in result.stdout.splitlines() if f.strip()]


# ── File discovery ─────────────────────────────────────────────────────────────

def _glob_to_regex(pattern: str) -> "re.Pattern[str]":
    """
    Convert a glob pattern with ``**`` support to a compiled regex.

    Rules:
    - ``**/``  matches zero or more path segments (including none)
    - ``**``   at end matches any remaining characters
    - ``*``    matches any sequence of non-separator characters
    - ``?``    matches a single non-separator character
    """
    pattern = pattern.replace("\\", "/")
    result = ""
    i = 0
    while i < len(pattern):
        if pattern[i : i + 3] == "**/":
            result += "(?:.+/)?"
            i += 3
        elif pattern[i : i + 2] == "**":
            result += ".*"
            i += 2
        elif pattern[i] == "*":
            result += "[^/]*"
            i += 1
        elif pattern[i] == "?":
            result += "[^/]"
            i += 1
        else:
            result += re.escape(pattern[i])
            i += 1
    return re.compile("^" + result + "$")


def path_matches_any(rel_posix: str, patterns: List[str]) -> bool:
    """Check a forward-slash relative path against a list of glob patterns."""
    name = rel_posix.rsplit("/", 1)[-1]
    for pattern in patterns:
        if fnmatch(rel_posix, pattern) or fnmatch(name, pattern):
            return True
        if "**" in pattern and _glob_to_regex(pattern).match(rel_posix):
            return True
    return False


def get_all_source_files(repo_root: Path, config: dict) -> Dict[str, List[Path]]:
    """Walk the full repo and return source files grouped by language name."""
    global_excludes = config.get("exclude_global", [])
    result: Dict[str, List[Path]] = {}

    for lang_name, lang_config in config["languages"].items():
        extensions = lang_config.get("extensions", [])
        excludes = global_excludes + lang_config.get("exclude_patterns", [])
        files = []

        for ext in extensions:
            for path in repo_root.rglob(f"*{ext}"):
                rel = path.relative_to(repo_root).as_posix()
                if not path_matches_any(rel, excludes):
                    files.append(path)

        if files:
            result[lang_name] = files

    return result


def filter_to_language(
    changed_rel_paths: List[str],
    repo_root: Path,
    config: dict,
) -> Dict[str, List[Path]]:
    """From a list of changed relative paths, return those that match each language."""
    global_excludes = config.get("exclude_global", [])
    result: Dict[str, List[Path]] = {}

    for lang_name, lang_config in config["languages"].items():
        extensions = set(lang_config.get("extensions", []))
        excludes = global_excludes + lang_config.get("exclude_patterns", [])
        files = []

        for rel in changed_rel_paths:
            if not any(rel.endswith(ext) for ext in extensions):
                continue
            rel_posix = rel.replace("\\", "/")
            if path_matches_any(rel_posix, excludes):
                continue
            full = repo_root / rel
            if full.exists():
                files.append(full)

        if files:
            result[lang_name] = files

    return result


# ── Domain resolution ──────────────────────────────────────────────────────────

def resolve_domain(file_rel: str, config: dict) -> Tuple[str, List[str]]:
    """
    Map a relative file path to a domain name and its tags.
    Matches the ordered domain list — first match wins.
    The last domain entry should be a catch-all (path: "**").
    """
    for domain in config["domains"]:
        for pattern in domain.get("paths", []):
            if fnmatch(file_rel, pattern) or fnmatch(file_rel.replace("\\", "/"), pattern):
                return domain["name"], domain.get("tags", [])
    return "general", []


# ── ast-grep extraction ────────────────────────────────────────────────────────

# ast-grep uses different language identifiers than our config keys
_AST_GREP_LANG = {
    "rust":       "rust",
    "typescript": "ts",
    "javascript": "js",
    "python":     "python",
    "go":         "go",
    "java":       "java",
    "csharp":     "cs",
}

# Windows command-line max is ~8191 chars; batch files to stay well under
_ASTGREP_BATCH = 40


def check_ast_grep() -> bool:
    try:
        result = subprocess.run(["ast-grep", "--version"], capture_output=True, timeout=10)
        return result.returncode == 0
    except (subprocess.TimeoutExpired, OSError):
        return False


def _run_ast_grep_pattern(
    pattern: str,
    lang: str,
    files: List[Path],
    repo_root: Path,
) -> List[dict]:
    """Run one ast-grep pattern against a batch of files. Returns raw match dicts."""
    all_matches: List[dict] = []
    file_strs = [str(f) for f in files]

    for i in range(0, len(file_strs), _ASTGREP_BATCH):
        batch = file_strs[i : i + _ASTGREP_BATCH]
        cmd = ["ast-grep", "run", "--pattern", pattern, "--lang", lang, "--json"] + batch

        try:
            result = subprocess.run(
                cmd,
                cwd=repo_root,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=300,
            )
        except subprocess.TimeoutExpired:
            print(
                f"    ast-grep: timed out scanning batch of {len(batch)} files — skipping",
                file=sys.stderr,
            )
            continue

        # returncode 1 = no matches (not an error)
        if result.returncode not in (0, 1):
            if result.stderr.strip():
                # Log the first line only — ast-grep is noisy about parse errors
                first_err = result.stderr.strip().splitlines()[0]
                print(f"    ast-grep: {first_err}", file=sys.stderr)
            continue

        if not result.stdout.strip():
            continue

        try:
            matches = json.loads(result.stdout)
            if isinstance(matches, list):
                all_matches.extend(matches)
        except json.JSONDecodeError:
            print(f"    Warning: Could not parse ast-grep JSON for pattern '{pattern[:40]}'",
                  file=sys.stderr)

    return all_matches


def _extract_name(match: dict) -> str:
    """Pull the $NAME metavariable out of an ast-grep match."""
    try:
        return match["metaVariables"]["single"]["NAME"]["text"].strip()
    except (KeyError, TypeError):
        return ""


def _extract_signature(text: str, kind: str, max_chars: int = 200) -> str:
    """
    Extract the signature (not the body) from matched text.
    For functions/methods: everything up to the opening brace.
    For types/structs: first line only.
    """
    lines = text.strip().splitlines()
    if not lines:
        return ""

    if kind in ("fn", "method"):
        sig_parts: List[str] = []
        for line in lines[:6]:  # Never take more than 6 lines for a signature
            sig_parts.append(line.strip())
            if "{" in line:
                break
        sig = " ".join(sig_parts)
        # Strip everything from the opening brace onward
        brace = sig.find("{")
        if brace != -1:
            sig = sig[:brace].strip()
    else:
        sig = lines[0].strip()

    return sig[:max_chars]


def extract_symbols_for_language(
    lang_name: str,
    lang_config: dict,
    files: List[Path],
    repo_root: Path,
    config: dict,
) -> List[Symbol]:
    ast_lang = _AST_GREP_LANG.get(lang_name, lang_name)
    seen_keys: set = set()
    symbols: List[Symbol] = []

    for symbol_def in lang_config.get("symbols", []):
        pattern    = symbol_def["pattern"]
        kind       = symbol_def["kind"]
        extra_tags = symbol_def.get("tags", [])
        name_filter = symbol_def.get("filter")

        matches = _run_ast_grep_pattern(pattern, ast_lang, files, repo_root)

        for match in matches:
            name = _extract_name(match)
            if not name:
                continue

            # Filters defined in config (e.g. skip private Python names)
            if name_filter == "not_private" and name.startswith("_"):
                continue

            file_abs = match.get("file", "")
            if not file_abs:
                continue

            try:
                file_rel = Path(file_abs).relative_to(repo_root).as_posix()
            except ValueError:
                file_rel = file_abs.replace("\\", "/")

            # ast-grep lines are 0-indexed
            line = match.get("range", {}).get("start", {}).get("line", 0) + 1

            # Deduplicate: same symbol matched by multiple patterns.
            # Line is included so that same-named symbols in one file
            # (e.g. pub fn new() across multiple impl blocks) are kept.
            key = f"{file_rel}::{name}::{line}"
            if key in seen_keys:
                continue
            seen_keys.add(key)

            domain, domain_tags = resolve_domain(file_rel, config)
            signature = _extract_signature(match.get("text", ""), kind)
            tags = sorted(set(extra_tags + domain_tags))

            symbols.append(Symbol(
                name=name,
                kind=kind,
                file=file_rel,
                line=line,
                signature=signature,
                language=lang_name,
                domain=domain,
                tags=tags,
            ))

    return symbols


def extract_all_symbols(
    files_by_lang: Dict[str, List[Path]],
    repo_root: Path,
    config: dict,
) -> List[Symbol]:
    all_symbols: List[Symbol] = []

    for lang_name, files in files_by_lang.items():
        lang_config = config["languages"].get(lang_name)
        if not lang_config:
            continue
        print(f"  Scanning {len(files):>4} {lang_name} files...")
        syms = extract_symbols_for_language(lang_name, lang_config, files, repo_root, config)
        print(f"           {len(syms):>4} symbols found")
        all_symbols.extend(syms)

    return all_symbols


# ── Catalog I/O ────────────────────────────────────────────────────────────────

_TABLE_HEADER = (
    "| Name | Kind | Location | Description | Tags |\n"
    "|------|------|----------|-------------|------|\n"
)


def _parse_table_row(row: str, domain: str) -> Optional[CatalogEntry]:
    """Parse one markdown table row back into a CatalogEntry. Returns None on bad rows."""
    cells = [c.strip() for c in row.strip().strip("|").split("|")]
    if len(cells) < 5:
        return None

    name = cells[0].strip("`").strip()
    kind = cells[1].strip()
    loc_raw = cells[2].strip().strip("`").strip()
    description = cells[3].strip()
    tags_raw = cells[4].strip()

    if not name or name == "Name":  # Skip header rows
        return None

    # Location format is "file:line"
    file_str, _, line_str = loc_raw.rpartition(":")
    try:
        line = int(line_str)
    except ValueError:
        file_str = loc_raw
        line = 0

    tags = [t.strip() for t in tags_raw.split(",") if t.strip()] if tags_raw else []

    return CatalogEntry(
        key=f"{file_str}::{name}",
        name=name,
        kind=kind,
        file=file_str,
        line=line,
        description=description,
        tags=tags,
        domain=domain,
    )


def load_existing_catalog(config: dict, repo_root: Path) -> Dict[str, CatalogEntry]:
    """Load all per-domain catalog files into a key → CatalogEntry dict."""
    output_dir = repo_root / config["catalog"]["output_dir"]
    entries: Dict[str, CatalogEntry] = {}

    if not output_dir.exists():
        return entries

    for md_file in sorted(output_dir.glob("*.md")):
        if md_file.stem == "index":
            continue
        domain = md_file.stem

        with open(md_file, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip()
                if not line.startswith("|"):
                    continue
                # Skip separator rows (all dashes and pipes)
                inner = line.replace("|", "").replace("-", "").replace(" ", "")
                if not inner:
                    continue
                entry = _parse_table_row(line, domain)
                if entry:
                    entries[entry.key] = entry

    return entries


# ── Diffing ────────────────────────────────────────────────────────────────────

def diff_catalog(
    existing: Dict[str, CatalogEntry],
    extracted: List[Symbol],
    deleted_files: List[str],
) -> Tuple[List[Symbol], Dict[str, CatalogEntry], set]:
    """
    Compare extracted symbols against the existing catalog.

    Returns:
        new_symbols       Symbols not yet in the catalog — need descriptions
        unchanged_entries Existing entries that are still valid
        removed_keys      Keys to prune from the catalog
    """
    extracted_keys = {sym.key for sym in extracted}
    deleted_set = {f.replace("\\", "/") for f in deleted_files}

    removed_keys: set = set()
    for key, entry in existing.items():
        if key not in extracted_keys or entry.file in deleted_set:
            removed_keys.add(key)

    new_symbols = [sym for sym in extracted if sym.key not in existing]

    unchanged_entries = {
        key: entry
        for key, entry in existing.items()
        if key not in removed_keys
    }

    return new_symbols, unchanged_entries, removed_keys


# ── LLM description generation ────────────────────────────────────────────────

_DESCRIPTION_SYSTEM = """\
You generate concise catalog descriptions for code symbols.

Rules:
- Maximum 15 words per description
- Start with an active verb: Validates..., Returns..., Converts..., Parses...
- Be specific about what the code DOES — avoid "handles", "manages", "processes"
- Do not restate the symbol name
- Include a constraint if it matters: "Panics if slice is empty", "Must be called after init()"

Return ONLY valid JSON — no explanation, no code fences:
{"descriptions": {"<key>": "<description>", ...}}\
"""


def generate_descriptions(symbols: List[Symbol], config: dict) -> List[Symbol]:
    """
    Call the Anthropic API to generate descriptions for new symbols.
    Batches calls to minimise latency and cost.
    Symbols with failed generation receive a placeholder; they are NOT omitted.
    """
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("  Warning: ANTHROPIC_API_KEY not set — using placeholder descriptions.",
              file=sys.stderr)
        for sym in symbols:
            sym.description = f"{sym.kind} in {sym.file}"
        return symbols

    try:
        import anthropic as _anthropic
    except ImportError:
        print(
            "Error: 'anthropic' package not found. Install it with: pip install anthropic",
            file=sys.stderr,
        )
        for sym in symbols:
            sym.description = f"{sym.kind} in {sym.file}"
        return symbols

    client = _anthropic.Anthropic(api_key=api_key)
    llm_config = config.get("llm", {})
    model      = llm_config.get("model", "claude-haiku-4-5-20251001")
    batch_size = llm_config.get("batch_size", 20)

    descriptions: Dict[str, str] = {}

    for i in range(0, len(symbols), batch_size):
        batch = symbols[i : i + batch_size]
        batch_num = i // batch_size + 1
        total_batches = (len(symbols) + batch_size - 1) // batch_size
        print(f"  Generating descriptions: batch {batch_num}/{total_batches} ({len(batch)} symbols)...")

        payload = [
            {
                "key":       sym.key,
                "name":      sym.name,
                "kind":      sym.kind,
                "signature": sym.signature,
                "file":      sym.file,
            }
            for sym in batch
        ]

        try:
            response = client.messages.create(
                model=model,
                max_tokens=1024,
                system=_DESCRIPTION_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": (
                        "Generate descriptions for these symbols:\n\n"
                        + json.dumps(payload, indent=2)
                    ),
                }],
            )

            text = response.content[0].text.strip()

            # Strip accidental code fences
            if text.startswith("```"):
                parts = text.split("```")
                text = parts[1].lstrip("json").strip() if len(parts) > 1 else text

            result = json.loads(text)
            descriptions.update(result.get("descriptions", {}))

        except json.JSONDecodeError as e:
            print(f"    Warning: Could not parse LLM response for batch {batch_num}: {e}",
                  file=sys.stderr)
            for sym in batch:
                descriptions.setdefault(sym.key, f"{sym.kind} — description unavailable")

        except _anthropic.APIError as e:
            print(f"    Warning: Anthropic API error for batch {batch_num}: {e}",
                  file=sys.stderr)
            for sym in batch:
                descriptions.setdefault(sym.key, f"{sym.kind} — description unavailable")

    # Attach descriptions
    for sym in symbols:
        sym.description = descriptions.get(sym.key, f"A {sym.kind} in {sym.file}")

    return symbols


# ── Catalog writing ────────────────────────────────────────────────────────────

def _symbol_to_entry(sym: Symbol) -> CatalogEntry:
    return CatalogEntry(
        key=sym.key,
        name=sym.name,
        kind=sym.kind,
        file=sym.file,
        line=sym.line,
        description=sym.description,
        tags=sym.tags,
        domain=sym.domain,
    )


def _format_row(entry: CatalogEntry) -> str:
    tags_str = ", ".join(sorted(entry.tags)) if entry.tags else ""
    return (
        f"| `{entry.name}` | {entry.kind} | {entry.location} "
        f"| {entry.description} | {tags_str} |"
    )


def _header_block(title: str, config: dict, commit: Optional[str]) -> List[str]:
    commit_ref = f" · commit `{commit[:8]}`" if commit else ""
    timestamp  = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    return [
        f"# Catalog: {title}",
        "",
        f"> Auto-generated by `scripts/update_catalog.py`{commit_ref} · {timestamp}",
        "> Do not edit manually — run the script to regenerate.",
        "",
    ]


def write_domain_file(
    domain_name: str,
    entries: List[CatalogEntry],
    config: dict,
    output_dir: Path,
    commit: Optional[str],
) -> None:
    domain_desc = next(
        (d.get("description", "") for d in config["domains"] if d["name"] == domain_name),
        "",
    )

    title = domain_name.replace("-", " ").title()
    lines = _header_block(title, config, commit)

    if domain_desc:
        lines += [domain_desc, ""]

    lines.append(_TABLE_HEADER.rstrip())
    for entry in sorted(entries, key=lambda e: e.name.lower()):
        lines.append(_format_row(entry))
    lines.append("")

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"{domain_name}.md"
    out_path.write_text("\n".join(lines), encoding="utf-8")


def write_index_file(
    all_entries: List[CatalogEntry],
    config: dict,
    output_dir: Path,
    commit: Optional[str],
) -> None:
    by_domain: Dict[str, List[CatalogEntry]] = {}
    for entry in all_entries:
        by_domain.setdefault(entry.domain, []).append(entry)

    lines = _header_block("Index", config, commit)
    lines += [
        "## Domains",
        "",
        "| Domain | Entries | Description |",
        "|--------|---------|-------------|",
    ]

    for domain_name in sorted(by_domain.keys()):
        entries = by_domain[domain_name]
        desc = next(
            (d.get("description", "") for d in config["domains"] if d["name"] == domain_name),
            "",
        )
        lines.append(f"| [{domain_name}]({domain_name}.md) | {len(entries)} | {desc} |")

    lines += [
        "",
        f"**Total: {len(all_entries)} entries across {len(by_domain)} domains**",
        "",
        "## All Entries",
        "",
        _TABLE_HEADER.rstrip(),
    ]

    for entry in sorted(all_entries, key=lambda e: (e.domain, e.name.lower())):
        lines.append(_format_row(entry))
    lines.append("")

    (output_dir / "index.md").write_text("\n".join(lines), encoding="utf-8")


def write_catalog(
    final_entries: Dict[str, CatalogEntry],
    config: dict,
    repo_root: Path,
    commit: Optional[str],
) -> None:
    output_dir = repo_root / config["catalog"]["output_dir"]

    by_domain: Dict[str, List[CatalogEntry]] = {}
    for entry in final_entries.values():
        by_domain.setdefault(entry.domain, []).append(entry)

    # Write per-domain files
    for domain_name, entries in by_domain.items():
        write_domain_file(domain_name, entries, config, output_dir, commit)

    # Remove files for domains that are now empty
    existing_files = set(output_dir.glob("*.md")) - {output_dir / "index.md"}
    active_files   = {output_dir / f"{d}.md" for d in by_domain}
    for stale in existing_files - active_files:
        stale.unlink()
        print(f"  Removed empty domain file: {stale.name}")

    # Write master index
    write_index_file(list(final_entries.values()), config, output_dir, commit)

    total_domains = len(by_domain)
    total_entries = len(final_entries)
    print(f"  Written: {output_dir.as_posix()}/")
    print(f"  {total_entries} entries across {total_domains} domains")


# ── State management ───────────────────────────────────────────────────────────

def load_state(config: dict, repo_root: Path) -> dict:
    state_path = repo_root / config["catalog"]["state_file"]
    if not state_path.exists():
        return {}
    try:
        return json.loads(state_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def save_state(
    config: dict,
    repo_root: Path,
    commit: Optional[str],
    entry_count: int,
) -> None:
    state_path = repo_root / config["catalog"]["state_file"]
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state = {
        "last_commit":  commit,
        "last_run":     datetime.now(timezone.utc).isoformat(),
        "entry_count":  entry_count,
    }
    state_path.write_text(json.dumps(state, indent=2), encoding="utf-8")


# ── Entry point ────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Update the codebase catalog in docs/catalog/.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--incremental", action="store_true",
        help="Only process files changed since last run (much faster)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print what would change without writing any files",
    )
    parser.add_argument(
        "--config", default="catalog.config.yml",
        help="Path to config file (default: catalog.config.yml)",
    )
    parser.add_argument(
        "--domain", metavar="DOMAIN",
        help="Process a single domain only (useful for debugging)",
    )
    args = parser.parse_args()

    # ── Pre-flight ─────────────────────────────────────────────────────────────

    if not check_ast_grep():
        print("Error: ast-grep not found on PATH.", file=sys.stderr)
        print("  cargo install ast-grep", file=sys.stderr)
        print("  Or: https://ast-grep.github.io/guide/quick-start.html", file=sys.stderr)
        sys.exit(1)

    config    = load_config(args.config)
    repo_root = find_repo_root()
    commit    = get_current_commit(repo_root)
    state     = load_state(config, repo_root)

    print(f"Catalog updater")
    print(f"  Repo:   {repo_root}")
    print(f"  Commit: {commit[:8] if commit else 'none'}")

    # ── File scope ─────────────────────────────────────────────────────────────

    deleted_files: List[str] = []
    last_commit = state.get("last_commit")

    if args.incremental and last_commit:
        print(f"  Mode:   incremental (last indexed: {last_commit[:8]})")
        changed = get_changed_files(repo_root, last_commit)

        if changed is None:
            # get_changed_files already printed a warning
            files_by_lang = get_all_source_files(repo_root, config)
        elif not changed:
            deleted_files = get_deleted_files(repo_root, last_commit)
            if not deleted_files:
                print("\nNo changes since last run. Catalog is up to date.")
                return
            else:
                print(f"  {len(deleted_files)} files deleted — pruning catalog entries")
                files_by_lang = {}   # Nothing to extract; only prune
        else:
            deleted_files = get_deleted_files(repo_root, last_commit)
            print(f"  {len(changed)} changed, {len(deleted_files)} deleted")
            files_by_lang = filter_to_language(changed, repo_root, config)
    else:
        mode = "full (no prior state)" if not last_commit else "full (forced)"
        print(f"  Mode:   {mode}")
        files_by_lang = get_all_source_files(repo_root, config)

    # ── Load existing catalog ──────────────────────────────────────────────────

    existing = load_existing_catalog(config, repo_root)
    print(f"  Existing catalog: {len(existing)} entries\n")

    # ── Extract symbols ────────────────────────────────────────────────────────

    print("Extracting symbols...")
    extracted = extract_all_symbols(files_by_lang, repo_root, config)

    # ── Domain filter (--domain flag) ─────────────────────────────────────────

    if args.domain:
        extracted = [s for s in extracted if s.domain == args.domain]
        existing  = {k: v for k, v in existing.items() if v.domain == args.domain}
        print(f"\nDomain filter applied: '{args.domain}' — {len(extracted)} symbols in scope")

    # ── Diff ───────────────────────────────────────────────────────────────────

    new_symbols, unchanged_entries, removed_keys = diff_catalog(
        existing, extracted, deleted_files,
    )

    print(
        f"\nDiff:  {len(new_symbols)} new | "
        f"{len(unchanged_entries)} unchanged | "
        f"{len(removed_keys)} removed"
    )

    # ── Dry run ────────────────────────────────────────────────────────────────

    if args.dry_run:
        print("\n── Dry run — no files written ──────────────────────────")
        if new_symbols:
            print(f"\nNew ({len(new_symbols)}):")
            for sym in sorted(new_symbols, key=lambda s: s.key):
                print(f"  + [{sym.domain}] {sym.name} ({sym.kind})  {sym.file}:{sym.line}")
        if removed_keys:
            print(f"\nRemoved ({len(removed_keys)}):")
            for key in sorted(removed_keys):
                print(f"  - {key}")
        if not new_symbols and not removed_keys:
            print("  Nothing would change.")
        return

    # ── Generate descriptions ──────────────────────────────────────────────────

    if new_symbols:
        print(f"\nGenerating descriptions for {len(new_symbols)} new symbols...")
        new_symbols = generate_descriptions(new_symbols, config)

    # ── Merge and write ────────────────────────────────────────────────────────

    new_entries = {sym.key: _symbol_to_entry(sym) for sym in new_symbols}
    final_entries: Dict[str, CatalogEntry] = {**unchanged_entries, **new_entries}

    print("\nWriting catalog...")
    write_catalog(final_entries, config, repo_root, commit)

    # ── Update state ───────────────────────────────────────────────────────────

    # Don't advance the state pointer for partial (--domain) runs,
    # because other domains may have changed files we didn't scan.
    if not args.domain:
        save_state(config, repo_root, commit, len(final_entries))

    print("\nDone.")


if __name__ == "__main__":
    main()
