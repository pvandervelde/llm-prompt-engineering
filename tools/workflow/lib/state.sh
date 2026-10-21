#!/usr/bin/env bash
# Read/write helpers for the workflow state file's machine-managed header.
#
# The header is a fixed set of "**Field:** value" lines plus a "## Existing
# Work" section the engine appends to. Everything else in the file (Standards,
# Context Bundle, etc.) is written by the conductor/agent, never by this
# engine, and these functions never touch it.

# Prints the value of **Field:** line, or empty if absent.
state_get_field() {
  local file="$1" field="$2"
  [ -f "$file" ] || return 0
  { grep -m1 -E "^\*\*${field}:\*\*" "$file" || true; } | sed -E "s/^\*\*${field}:\*\* *//"
}

# Replaces (or inserts, if missing) a **Field:** line with a new value. A
# missing field is inserted right before the first "## " heading (i.e. at
# the end of the header block), never appended at EOF -- EOF may be inside
# or after a section whose own rewrite logic (e.g.
# state_clear_blocking_issues, which stops skipping only at the next
# "## " heading) assumes nothing meaningful follows it.
state_set_field() {
  local file="$1" field="$2" value="$3"
  if grep -q -E "^\*\*${field}:\*\*" "$file" 2>/dev/null; then
    local esc_value
    esc_value=$(printf '%s' "$value" | sed -E 's/[&/\]/\\&/g')
    sed -i -E "s/^\*\*${field}:\*\*.*/\*\*${field}:\*\* ${esc_value}/" "$file"
  else
    awk -v field="$field" -v value="$value" '
      BEGIN { inserted = 0 }
      !inserted && /^## / { print "**" field ":** " value; inserted = 1 }
      { print }
      END { if (!inserted) print "**" field ":** " value }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  fi
}

# Space-separated list of phase ids already completed in the current
# parallel stage (reset whenever a new stage begins).
state_phases_done_get() {
  local file="$1"
  state_get_field "$file" "Phases Done"
}

state_phases_done_add() {
  local file="$1" phase_id="$2"
  local current new
  current=$(state_phases_done_get "$file")
  case " $current " in
    *" $phase_id "*) new="$current" ;;
    *) new="${current:+$current }$phase_id" ;;
  esac
  state_set_field "$file" "Phases Done" "$new"
}

state_phases_done_clear() {
  local file="$1"
  state_set_field "$file" "Phases Done" ""
}

# Appends one bullet under "## Blocking Issues", replacing a lone "[None]"
# placeholder on first use.
state_append_blocking_issue() {
  local file="$1" line="$2"
  awk -v newline="- ${line}" '
    BEGIN { done = 0 }
    {
      print
      if (!done && $0 == "## Blocking Issues") {
        getline nxt
        if (nxt != "[None]") print nxt
        print newline
        done = 1
      }
    }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# Resets "## Blocking Issues" to "[None]", discarding whatever was there.
# Called once a gate that previously paused finally advances clean.
state_clear_blocking_issues() {
  local file="$1"
  awk '
    BEGIN { skip = 0 }
    $0 == "## Blocking Issues" { print; print "[None]"; skip = 1; next }
    skip && /^## / { skip = 0 }
    skip { next }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# Appends one bullet under "## Existing Work", replacing a lone placeholder
# line ("[None yet]") on first use.
state_append_existing_work() {
  local file="$1" line="$2"
  awk -v newline="- ${line}" '
    BEGIN { done = 0 }
    {
      print
      if (!done && $0 == "## Existing Work") {
        getline nxt
        if (nxt != "[None yet]") print nxt
        print newline
        done = 1
      }
    }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# Prints the recorded "<mode> (<source>)" string for one phase under
# "## Isolation", or empty if that phase's isolation mode hasn't been resolved
# yet for this task.
state_isolation_get() {
  local file="$1" phase_id="$2"
  [ -f "$file" ] || return 0
  awk -v phase="$phase_id" '
    $0 == "## Isolation" { inb=1; next }
    inb && /^## / { exit }
    inb && $0 ~ "^" phase ": " { sub("^" phase ": ", ""); print; exit }
  ' "$file"
}

# Upserts one "<phase>: <mode> (<source>)" line under "## Isolation" --
# replacing that phase's existing line if present, replacing a lone
# "[None yet]" placeholder on first use, or appending otherwise. Unlike
# state_append_existing_work/state_append_blocking_issue (pure append), each
# phase gets at most one line here, so an existing line for the same phase is
# updated in place rather than duplicated (e.g. a task-level override
# recorded after next already cached the repo-default mode).
state_isolation_set() {
  local file="$1" phase_id="$2" mode="$3" source="$4"
  local newline="${phase_id}: ${mode} (${source})"
  awk -v phase="$phase_id" -v newline="$newline" '
    BEGIN { inb = 0; replaced = 0; section_seen = 0 }
    $0 == "## Isolation" { print; inb = 1; section_seen = 1; next }
    inb && /^## / {
      if (!replaced) { print newline; replaced = 1 }
      inb = 0
      print
      next
    }
    inb && $0 == "[None yet]" { next }
    inb && $0 ~ "^" phase ": " { print newline; replaced = 1; next }
    { print }
    END { if (section_seen && !replaced) print newline }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# Writes the initial skeleton for a new task. Fails (returns 1) rather than
# overwriting if a state file already exists for a *different* task -- the
# caller must resolve that before calling init.
state_init() {
  local file="$1" task="$2" pipeline="$3" branch="$4" first_phase="$5"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
# Workflow State — ${task}

**Task:** ${task}
**Pipeline:** ${pipeline}
**Branch:** ${branch}
**Current Phase:** ${first_phase}
**Phases Done:**
**Status:** in-progress

## Standards
[Not yet extracted — filled by the Conductor, not this engine]

## Toolchain
[Not yet extracted]

## Context
[Not yet extracted — software: Relevant Assertions / Interface Contract / Catalog Slice /
Security Rules; infrastructure: Module Spec / Conventions / Module Registry Slice. The
engine doesn't know pipeline-specific section shapes; see tools/workflow/README.md.]

## Existing Work
[None yet]

## Blocking Issues
[None]

## Isolation
[None yet]
EOF
}
