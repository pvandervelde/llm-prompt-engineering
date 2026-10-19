#!/usr/bin/env bash
# Minimal, targeted extraction over workflow/pipelines.yml.
#
# This is NOT a general YAML parser. It understands exactly the subset
# pipelines.yml uses: a fixed-indentation map of pipelines, each with scalar
# keys, a `phases:` list of maps (each item starting with `- id: <X>`), inline
# bracket lists (`[a, b]`) for pauseWhen/parallelWith, and one level of nested
# map (`skipWhen:`) under a phase. If pipelines.yml's shape changes beyond
# this, these functions need to change with it -- that coupling is deliberate
# and documented in workflow/README.md.

# Prints the lines belonging to pipeline $2 in file $1, dedented by nothing
# (still 4+ space indented) -- i.e. everything between "  <pipeline>:" and
# the next 2-space-indented key (or EOF).
pl_pipeline_block() {
  local file="$1" pipeline="$2"
  awk -v pl="  ${pipeline}:" '
    $0 == pl { found=1; next }
    found && /^  [A-Za-z]/ { exit }
    found { print }
  ' "$file"
}

# Scalar value of a top-level-within-pipeline key, e.g. stateFile, branchPrefix.
# `|| true`: the field may legitimately be absent (e.g. onPass, skipWhen) --
# under `set -e -o pipefail` a plain grep miss must not abort the caller.
pl_scalar() {
  local block="$1" key="$2"
  printf '%s\n' "$block" \
    | { grep -m1 -E "^    ${key}:" || true; } \
    | sed -E "s/^    ${key}: *//" \
    | sed -E 's/^"(.*)"$/\1/'
}

# Ordered list of phase ids in a pipeline block.
pl_phase_ids() {
  local block="$1"
  printf '%s\n' "$block" | grep -E '^      - id: ' | sed -E 's/^      - id: *//'
}

# Prints the lines belonging to one phase (from "- id: X" to the next "- id:"
# or dedent back to a pipeline-level key).
pl_phase_block() {
  local block="$1" phase_id="$2"
  printf '%s\n' "$block" | awk -v id="      - id: ${phase_id}" '
    $0 == id { found=1; print; next }
    found && /^      - id:/ { exit }
    found && /^    [A-Za-z]/ { exit }
    found { print }
  '
}

# Scalar field within a phase block, e.g. agent, advance, onPass (onPass is
# optional -- absence is normal, not an error; see pl_scalar's note on `|| true`).
pl_phase_scalar() {
  local phase_block="$1" field="$2"
  printf '%s\n' "$phase_block" \
    | { grep -m1 -E "^        ${field}:" || true; } \
    | sed -E "s/^        ${field}: *//" \
    | sed -E 's/^"(.*)"$/\1/'
}

# List field within a phase block, inline bracket style only (`[a, b]`).
# Prints one item per line; prints nothing if the field is absent or empty.
pl_phase_list() {
  local phase_block="$1" field="$2"
  local raw
  raw=$(printf '%s\n' "$phase_block" | { grep -m1 -E "^        ${field}:" || true; } | sed -E "s/^        ${field}: *//")
  raw="${raw#\[}"
  raw="${raw%\]}"
  [ -z "$raw" ] && return 0
  printf '%s\n' "$raw" | tr ',' '\n' | sed -E 's/^ +//; s/ +$//'
}

# True (exit 0) if $2 is an exact element of the newline-separated list $1
# (as pl_phase_list returns it). Deliberately not `case " $1 " in *" $2 "*)`
# -- that pattern silently fails to match ANY element of a multi-item list,
# since embedded newlines (not spaces) separate the items, so neither the
# leading- nor trailing-space requirement is ever satisfied for an interior
# element.
pl_list_contains() {
  local list="$1" item="$2" line
  while IFS= read -r line; do
    [ "$line" = "$item" ] && return 0
  done <<< "$list"
  return 1
}

# Scalar value nested one level under skipWhen: within a phase block.
pl_phase_skipwhen() {
  local phase_block="$1" key="$2"
  printf '%s\n' "$phase_block" \
    | { grep -m1 -E "^          ${key}:" || true; } \
    | sed -E "s/^          ${key}: *//"
}
