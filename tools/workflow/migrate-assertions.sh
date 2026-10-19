#!/usr/bin/env bash
# One-shot migration: back-fills fenced ```yaml blocks into an existing
# docs/spec/assertions.md written in the pre-#59 prose-only format
# (### ASSERT-NNNN: <name> / **Module:** / **Given** / **When** / **Then** /
# **And**). Idempotent -- skips any ASSERT-NNNN section that already has a
# yaml block immediately after its heading. Run once per repo; after that,
# architect.md writes both forms together on every new assertion, so this
# script has nothing left to do.
#
# Usage: bash tools/workflow/migrate-assertions.sh [path/to/assertions.md]
# Defaults to docs/spec/assertions.md at the repo root.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$ROOT" ] || { echo "error: not inside a git repository" >&2; exit 1; }

FILE="${1:-${ROOT}/docs/spec/assertions.md}"
[ -f "$FILE" ] || { echo "error: $FILE does not exist" >&2; exit 1; }

# Security-tag heuristic -- mirrors the keywords architect.md's own tagging
# rule names (auth, validation, secrets, error handling). Best-effort: it
# gets a migrated file to a reviewable starting point, not a verified one.
is_security() {
  printf '%s' "$1" | grep -qiE 'auth|password|credential|secret|token|permission|valid|sanitiz|inject|session|encrypt'
}

mapfile -t lines < "$FILE"
out=()
migrated_count=0

i=0
n=${#lines[@]}
while [ "$i" -lt "$n" ]; do
  line="${lines[$i]}"
  out+=("$line")

  if [[ "$line" =~ ^###\ (ASSERT-[0-9]+): ]]; then
    assert_id="${BASH_REMATCH[1]}"
    # Peek past a possible blank line to see if this section is already migrated.
    # Don't advance `i` here -- just skip the insertion logic below and let the
    # normal per-line loop below copy the existing blank/yaml lines through as-is.
    next="${lines[$((i + 1))]:-}"
    [ -z "$next" ] && next="${lines[$((i + 2))]:-}"
    if [ "$next" = '```yaml' ]; then
      i=$((i + 1))
      continue
    fi

    # Scan forward within this section (until the next "### " heading or EOF)
    # for Module/Given/When/Then/And, without consuming lines yet.
    module="" given="" when="" then_="" and_=""
    j=$((i + 1))
    while [ "$j" -lt "$n" ]; do
      peek="${lines[$j]}"
      [[ "$peek" =~ ^###\  ]] && break
      case "$peek" in
        '**Module:**'*) module="${peek#\*\*Module:\*\* }" ;;
        '**Given**'*) given="${peek#\*\*Given\*\* }" ;;
        '**When**'*) when="${peek#\*\*When\*\* }" ;;
        '**Then**'*) then_="${peek#\*\*Then\*\* }" ;;
        '**And**'*) and_="${peek#\*\*And\*\* }" ;;
      esac
      j=$((j + 1))
    done

    if [ -n "$module" ] || [ -n "$given" ]; then
      out+=("")
      out+=('```yaml')
      out+=("id: ${assert_id}")
      out+=("module: ${module}")
      if is_security "${given} ${when} ${then_} ${and_}"; then
        out+=("tags: [security]")
      fi
      out+=("given: ${given}")
      out+=("when: ${when}")
      out+=("then: ${then_}")
      [ -n "$and_" ] && out+=("and: ${and_}")
      out+=('```')
      out+=("")
      migrated_count=$((migrated_count + 1))
    fi
  fi

  i=$((i + 1))
done

printf '%s\n' "${out[@]}" > "${FILE}.tmp" && mv "${FILE}.tmp" "$FILE"

echo "Migrated ${migrated_count} assertion(s) in: $FILE"
echo "Review the inserted yaml blocks (especially the [security] tag heuristic) before committing."
