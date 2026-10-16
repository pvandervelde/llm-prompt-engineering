#!/usr/bin/env bash
# Workflow engine (bash) -- deterministic branch resolution, phase sequencing,
# and gate evaluation for the pipelines defined in workflow/pipelines.yml.
# See workflow/README.md for the schema and tools/workflow/README.md for the
# CLI contract. Mirrors workflow.ps1 command-for-command.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/pipeline.sh
source "${SCRIPT_DIR}/lib/pipeline.sh"
# shellcheck source=lib/state.sh
source "${SCRIPT_DIR}/lib/state.sh"

VALID_REASONS="spec-gap blocked safety-critical-survivor formal-counterexample critical-finding fail"

die() {
  printf '{"error":"%s"}\n' "$1"
  exit 1
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || die "not inside a git repository"
}

pipelines_file() {
  echo "$(repo_root)/workflow/pipelines.yml"
}

json_escape() {
  printf '%s' "$1" | sed -E 's/\\/\\\\/g; s/"/\\"/g'
}

# ---- pipeline/state resolution -------------------------------------------

# Prints "<pipeline> <stateFilePath>" for the named pipeline.
resolve_named_pipeline() {
  local pipeline="$1"
  local root pfile block state_rel
  root="$(repo_root)"
  pfile="$(pipelines_file)"
  block=$(pl_pipeline_block "$pfile" "$pipeline")
  [ -n "$block" ] || die "unknown pipeline: ${pipeline}"
  state_rel=$(pl_scalar "$block" stateFile)
  echo "${pipeline} ${root}/${state_rel}"
}

# Prints "<pipeline> <stateFilePath>" by inspecting which default state file
# is active (exists and not complete). Errors if zero or more than one match.
resolve_active_pipeline() {
  local root pfile candidates=() names=() name block state_rel full status
  root="$(repo_root)"
  pfile="$(pipelines_file)"
  for name in software infrastructure; do
    block=$(pl_pipeline_block "$pfile" "$name")
    state_rel=$(pl_scalar "$block" stateFile)
    full="${root}/${state_rel}"
    if [ -f "$full" ]; then
      status=$(state_get_field "$full" "Status")
      if [ "$status" != "complete" ]; then
        candidates+=("$full")
        names+=("$name")
      fi
    fi
  done
  if [ "${#candidates[@]}" -eq 0 ]; then
    die "no active task; run 'init' first or pass --pipeline"
  elif [ "${#candidates[@]}" -gt 1 ]; then
    die "multiple active pipelines (${names[*]}); pass --pipeline to disambiguate"
  fi
  echo "${names[0]} ${candidates[0]}"
}

# ---- branch resolution (tech-lead.md Step 2b, infra-lead.md equivalent) --

derive_slug() {
  local task="$1" slug="$2"
  if [ -n "$slug" ]; then
    echo "$slug"
  else
    printf '%s' "$task" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
  fi
}

is_integration_branch() {
  local branch="$1"
  case "$branch" in
    main|master|develop|release/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolves the branch for `init`. Prints one line:
#   "use <branch>" | "create <branch>" | "ask <reason> <currentBranch>"
resolve_branch() {
  local task="$1" pipeline="$2" prefix="$3" state_file="$4" slug="$5"
  local current existing_task existing_branch
  current=$(git branch --show-current)

  if [ -f "$state_file" ]; then
    existing_task=$(state_get_field "$state_file" "Task")
    existing_branch=$(state_get_field "$state_file" "Branch")
  else
    existing_task=""
    existing_branch=""
  fi

  case "$current" in
    "${prefix}"*)
      if [ -n "$existing_task" ] && [ "$existing_task" != "$task" ]; then
        echo "ask wrong-task-branch ${current}"
      else
        echo "use ${current}"
      fi
      ;;
    *)
      if is_integration_branch "$current"; then
        echo "create ${prefix}$(derive_slug "$task" "$slug")"
      else
        echo "ask ambiguous-branch ${current}"
      fi
      ;;
  esac
}

# ---- commands --------------------------------------------------------------

cmd_init() {
  local task="" pipeline="" slug=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --task) task="$2"; shift 2 ;;
      --pipeline) pipeline="$2"; shift 2 ;;
      --slug) slug="$2"; shift 2 ;;
      *) die "init: unknown argument $1" ;;
    esac
  done
  [ -n "$task" ] || die "init: --task is required"
  [ -n "$pipeline" ] || die "init: --pipeline is required"

  local root pfile block state_rel state_file prefix
  root="$(repo_root)"
  pfile="$(pipelines_file)"
  block=$(pl_pipeline_block "$pfile" "$pipeline")
  [ -n "$block" ] || die "unknown pipeline: ${pipeline}"
  state_rel=$(pl_scalar "$block" stateFile)
  state_file="${root}/${state_rel}"
  prefix=$(pl_scalar "$block" branchPrefix)

  local resolution action arg1 arg2
  resolution=$(resolve_branch "$task" "$pipeline" "$prefix" "$state_file" "$slug")
  action=$(echo "$resolution" | cut -d' ' -f1)
  arg1=$(echo "$resolution" | cut -d' ' -f2)
  arg2=$(echo "$resolution" | cut -d' ' -f3-)

  local branch
  case "$action" in
    ask)
      printf '{"action":"ask","reason":"%s","currentBranch":"%s"}\n' "$(json_escape "$arg1")" "$(json_escape "$arg2")"
      exit 2
      ;;
    create)
      branch="$arg1"
      (cd "$root" && git switch -c "$branch" >/dev/null 2>&1) || (cd "$root" && git switch "$branch" >/dev/null 2>&1) || die "failed to create/switch to branch ${branch}"
      ;;
    use)
      branch="$arg1"
      ;;
  esac

  local first_phase first_agent
  first_phase=$(pl_phase_ids "$block" | head -n1)
  [ -n "$first_phase" ] || die "pipeline ${pipeline} has no phases"
  first_agent=$(pl_phase_scalar "$(pl_phase_block "$block" "$first_phase")" agent)

  state_init "$state_file" "$task" "$pipeline" "$branch" "$first_phase"

  printf '{"phase":"%s","agent":"%s","branch":"%s","stateFile":"%s"}\n' \
    "$(json_escape "$first_phase")" "$(json_escape "$first_agent")" "$(json_escape "$branch")" "$(json_escape "$state_file")"
}

# Checks the SPEC_REVIEW_GATE skip condition: a report exists whose verdict
# equals the required value and whose mtime is not older than the latest
# commit touching the watched path.
spec_review_fresh() {
  local root="$1" required_verdict="$2" watch_path="$3"
  local report report_mtime spec_commit_epoch verdict
  report=$(ls -1 "${root}/.llm/spec-review/"*.md 2>/dev/null | sort | tail -n1 || true)
  [ -n "$report" ] || return 1
  verdict=$({ grep -A1 -m1 '^## Verdict' "$report" 2>/dev/null || true; } | tail -n1 | tr -d '[:space:]')
  [ "$verdict" = "$required_verdict" ] || return 1
  report_mtime=$(stat -c %Y "$report" 2>/dev/null || stat -f %m "$report" 2>/dev/null || echo 0)
  spec_commit_epoch=$(cd "$root" && git log -1 --format=%ct -- "$watch_path" 2>/dev/null)
  spec_commit_epoch="${spec_commit_epoch:-0}"
  [ "$report_mtime" -ge "$spec_commit_epoch" ]
}

cmd_next() {
  local pipeline=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --pipeline) pipeline="$2"; shift 2 ;;
      *) die "next: unknown argument $1" ;;
    esac
  done

  local root pfile resolved name state_file block current_phase status
  root="$(repo_root)"
  pfile="$(pipelines_file)"
  if [ -n "$pipeline" ]; then
    resolved=$(resolve_named_pipeline "$pipeline")
  else
    resolved=$(resolve_active_pipeline)
  fi
  name=$(echo "$resolved" | cut -d' ' -f1)
  state_file=$(echo "$resolved" | cut -d' ' -f2-)
  [ -f "$state_file" ] || die "no state file for ${name}; run 'init' first"

  block=$(pl_pipeline_block "$pfile" "$name")
  current_phase=$(state_get_field "$state_file" "Current Phase")
  status=$(state_get_field "$state_file" "Status")

  if [ "$current_phase" = "DONE" ] || [ "$status" = "complete" ]; then
    printf '{"phases":[],"status":"complete","contextRefs":["%s"]}\n' "$(json_escape "$state_file")"
    return 0
  fi

  local phase_block advance
  phase_block=$(pl_phase_block "$block" "$current_phase")
  [ -n "$phase_block" ] || die "state file names unknown phase: ${current_phase}"
  advance=$(pl_phase_scalar "$phase_block" advance)

  if [ "$advance" = "conditional" ]; then
    local req_verdict watch_path
    req_verdict=$(pl_phase_skipwhen "$phase_block" reportVerdict)
    watch_path=$(pl_phase_skipwhen "$phase_block" reportNewerThan)
    if spec_review_fresh "$root" "$req_verdict" "$watch_path"; then
      # Auto-advance past this phase without invoking its agent.
      local next_id
      next_id=$(pl_phase_ids "$block" | awk -v cur="$current_phase" 'f{print; exit} $0==cur{f=1}')
      state_set_field "$state_file" "Current Phase" "${next_id:-DONE}"
      cmd_next_inner "$root" "$pfile" "$name" "$state_file"
      return 0
    fi
  fi

  cmd_next_inner "$root" "$pfile" "$name" "$state_file"
}

cmd_next_inner() {
  local root="$1" pfile="$2" name="$3" state_file="$4"
  local block current_phase phase_block parallel done_list phases_json first=1 id agent

  block=$(pl_pipeline_block "$pfile" "$name")
  current_phase=$(state_get_field "$state_file" "Current Phase")

  if [ "$current_phase" = "DONE" ]; then
    printf '{"phases":[],"status":"complete","contextRefs":["%s"]}\n' "$(json_escape "$state_file")"
    return 0
  fi

  phase_block=$(pl_phase_block "$block" "$current_phase")
  parallel=$(pl_phase_list "$phase_block" parallelWith)
  done_list=$(state_phases_done_get "$state_file")

  phases_json="["
  for id in "$current_phase" $parallel; do
    case " $done_list " in
      *" $id "*) continue ;;
    esac
    agent=$(pl_phase_scalar "$(pl_phase_block "$block" "$id")" agent)
    [ "$first" -eq 1 ] || phases_json+=","
    phases_json+=$(printf '{"phase":"%s","agent":"%s"}' "$(json_escape "$id")" "$(json_escape "$agent")")
    first=0
  done
  phases_json+="]"

  printf '{"phases":%s,"contextRefs":["%s"]}\n' "$phases_json" "$(json_escape "$state_file")"
}

cmd_gate() {
  local pipeline="" phase="" verdict="" actual="" target=""
  local reasons=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --pipeline) pipeline="$2"; shift 2 ;;
      --phase) phase="$2"; shift 2 ;;
      --verdict) verdict="$2"; shift 2 ;;
      --reason) reasons+=("$2"); shift 2 ;;
      --actual) actual="$2"; shift 2 ;;
      --target) target="$2"; shift 2 ;;
      *) die "gate: unknown argument $1" ;;
    esac
  done
  [ -n "$phase" ] || die "gate: --phase is required"
  [ -n "$verdict" ] || die "gate: --verdict is required"

  for r in "${reasons[@]:-}"; do
    [ -z "$r" ] && continue
    case " $VALID_REASONS " in
      *" $r "*) : ;;
      *) die "gate: unrecognized --reason '${r}' (see workflow/README.md for the fixed set)" ;;
    esac
  done

  local root pfile resolved name state_file block phase_block pausewhen
  root="$(repo_root)"
  pfile="$(pipelines_file)"
  if [ -n "$pipeline" ]; then
    resolved=$(resolve_named_pipeline "$pipeline")
  else
    resolved=$(resolve_active_pipeline)
  fi
  name=$(echo "$resolved" | cut -d' ' -f1)
  state_file=$(echo "$resolved" | cut -d' ' -f2-)
  [ -f "$state_file" ] || die "no state file for ${name}; run 'init' first"

  block=$(pl_pipeline_block "$pfile" "$name")
  phase_block=$(pl_phase_block "$block" "$phase")
  [ -n "$phase_block" ] || die "unknown phase: ${phase}"
  pausewhen=$(pl_phase_list "$phase_block" pauseWhen)

  local result="ADVANCE" blocking_reason=""

  # Threshold check always wins: never ADVANCE on an unmet threshold,
  # regardless of the claimed verdict.
  if [ -n "$actual" ] && [ -n "$target" ]; then
    if awk -v a="$actual" -v t="$target" 'BEGIN{exit !(a < t)}'; then
      result="FAIL"
      blocking_reason="threshold-unmet (actual=${actual} < target=${target})"
    fi
  fi

  if [ "$result" = "ADVANCE" ]; then
    for r in "${reasons[@]:-}"; do
      [ -z "$r" ] && continue
      case " $pausewhen " in
        *" $r "*)
          result="PAUSE"
          blocking_reason="$r"
          break
          ;;
      esac
    done
  fi

  state_append_existing_work "$state_file" "${phase}: verdict=${verdict} result=${result}$( [ -n "$blocking_reason" ] && printf ' (%s)' "$blocking_reason" )"

  local next_phase="null" onpass="null"
  if [ "$result" = "ADVANCE" ]; then
    local parallel done_list group onpass_raw
    parallel=$(pl_phase_list "$phase_block" parallelWith)
    state_phases_done_add "$state_file" "$phase"
    done_list=$(state_phases_done_get "$state_file")
    group_complete=1
    for id in "$phase" $parallel; do
      case " $done_list " in
        *" $id "*) : ;;
        *) group_complete=0 ;;
      esac
    done
    if [ "$group_complete" -eq 1 ]; then
      # Find the highest index among {phase, parallel...} in canonical phase
      # order, then return the phase right after it -- order-independent, so
      # it doesn't matter whether `phase` or one of its `parallel` siblings
      # was declared first in pipelines.yml.
      local ids=() next_id="" max_idx=-1 i g
      while IFS= read -r line; do ids+=("$line"); done < <(pl_phase_ids "$block")
      for i in "${!ids[@]}"; do
        for g in "$phase" $parallel; do
          if [ "${ids[$i]}" = "$g" ] && [ "$i" -gt "$max_idx" ]; then
            max_idx="$i"
          fi
        done
      done
      if [ "$max_idx" -ge 0 ] && [ $((max_idx + 1)) -lt "${#ids[@]}" ]; then
        next_id="${ids[$((max_idx + 1))]}"
      fi
      state_phases_done_clear "$state_file"
      state_set_field "$state_file" "Current Phase" "${next_id:-DONE}"
      state_set_field "$state_file" "Status" "in-progress"
      state_clear_blocking_issues "$state_file"
      if [ -n "$next_id" ]; then
        next_phase="\"${next_id}\""
      fi
      onpass_raw=$(pl_phase_scalar "$phase_block" onPass)
      [ -n "$onpass_raw" ] && onpass="\"${onpass_raw}\""
    else
      next_phase="\"${phase}\""
    fi
  else
    state_set_field "$state_file" "Status" "paused"
    state_append_blocking_issue "$state_file" "**[${phase}]** ${blocking_reason}"
  fi

  printf '{"result":"%s","nextPhase":%s,"onPass":%s}\n' "$result" "$next_phase" "$onpass"
}

cmd_complete() {
  local task="" pipeline=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --task) task="$2"; shift 2 ;;
      --pipeline) pipeline="$2"; shift 2 ;;
      *) die "complete: unknown argument $1" ;;
    esac
  done
  [ -n "$task" ] || die "complete: --task is required"

  local root resolved name state_file current_phase
  root="$(repo_root)"
  if [ -n "$pipeline" ]; then
    resolved=$(resolve_named_pipeline "$pipeline")
  else
    resolved=$(resolve_active_pipeline)
  fi
  name=$(echo "$resolved" | cut -d' ' -f1)
  state_file=$(echo "$resolved" | cut -d' ' -f2-)
  [ -f "$state_file" ] || die "no state file for ${name}; run 'init' first"

  current_phase=$(state_get_field "$state_file" "Current Phase")
  [ "$current_phase" = "DONE" ] || die "pipeline not finished (current phase: ${current_phase})"

  local marked="false" tasks_file="${root}/.llm/tasks.md"
  if [ -f "$tasks_file" ]; then
    if grep -q -E "^- \[ \] ${task} " "$tasks_file"; then
      sed -i -E "s/^- \[ \] ${task} /- [x] ${task} /" "$tasks_file"
      marked="true"
    fi
    # Also flip the structured task record's status, if this task id has one.
    awk -v target="$task" '
      BEGIN { inb = 0; idmatch = 0 }
      /^```yaml$/ { inb = 1; idmatch = 0; print; next }
      /^```$/ { inb = 0; print; next }
      inb && /^id: */ {
        v = $0; sub(/^id: */, "", v); gsub(/^"|"$/, "", v)
        idmatch = (v == target)
        print
        next
      }
      inb && idmatch && /^status: */ { print "status: done"; next }
      { print }
    ' "$tasks_file" > "${tasks_file}.tmp" && mv "${tasks_file}.tmp" "$tasks_file"
  fi

  state_set_field "$state_file" "Status" "complete"
  printf '{"status":"complete","task":"%s","taskMarked":%s}\n' "$(json_escape "$task")" "$marked"
}

# Reads the inline bracket-list for one domain under .tech-decisions.yml's
# top-level `classify:` key. Missing file or missing domain -> empty (no
# globs), which makes every path for that domain "none" rather than an error.
classify_globs() {
  local file="$1" domain="$2"
  [ -f "$file" ] || return 0
  local raw
  raw=$(awk '
    /^classify:/ { found=1; next }
    found && /^[A-Za-z]/ { exit }
    found { print }
  ' "$file" | { grep -m1 -E "^  ${domain}:" || true; } | sed -E "s/^  ${domain}: *//")
  raw="${raw#\[}"
  raw="${raw%\]}"
  [ -z "$raw" ] && return 0
  printf '%s\n' "$raw" | tr ',' '\n' | sed -E 's/^ +//; s/ +$//' | sed -E 's/^"(.*)"$/\1/'
}

# Classifies one path against one domain's globs. Prints "hit" once per
# matching glob (so the caller can detect a path matching >1 domain).
path_matches_domain() {
  local path="$1" globs="$2"
  local g matched=1
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    case "$path" in
      $g) matched=0 ;;
    esac
  done <<< "$globs"
  return $matched
}

cmd_classify() {
  local task="" paths=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --task) task="$2"; shift 2 ;;
      --path) paths+=("$2"); shift 2 ;;
      *) die "classify: unknown argument $1" ;;
    esac
  done

  local root tech_file
  root="$(repo_root)"
  tech_file="${root}/.tech-decisions.yml"

  if [ -n "$task" ]; then
    local tasks_file="${root}/.llm/tasks.md" block
    if [ -f "$tasks_file" ]; then
      block=$(awk -v id="$task" '
        $0 ~ "^- \\[[ x]\\] " id " " { found=1; print; next }
        found && /^- \[/ { exit }
        found { print }
      ' "$tasks_file")
      while IFS= read -r p; do
        [ -n "$p" ] && paths+=("$p")
      done < <(printf '%s\n' "$block" | { grep -oE 'docs/spec/[A-Za-z0-9_./*-]+' || true; })
    fi
  fi

  if [ "${#paths[@]}" -eq 0 ]; then
    printf '{"domain":"ambiguous","reason":"no-paths-resolved","paths":[]}\n'
    return 0
  fi

  local frontend_globs backend_globs infra_globs
  frontend_globs=$(classify_globs "$tech_file" frontend)
  backend_globs=$(classify_globs "$tech_file" backend)
  infra_globs=$(classify_globs "$tech_file" infrastructure)

  local verdict="" p path_domain hit_count paths_json="[" first=1
  for p in "${paths[@]}"; do
    path_domain="none"
    hit_count=0
    if path_matches_domain "$p" "$frontend_globs"; then path_domain="frontend"; hit_count=$((hit_count + 1)); fi
    if path_matches_domain "$p" "$backend_globs"; then path_domain="backend"; hit_count=$((hit_count + 1)); fi
    if path_matches_domain "$p" "$infra_globs"; then path_domain="infrastructure"; hit_count=$((hit_count + 1)); fi
    [ "$hit_count" -gt 1 ] && path_domain="ambiguous"

    [ "$first" -eq 1 ] || paths_json+=","
    paths_json+=$(printf '{"path":"%s","domain":"%s"}' "$(json_escape "$p")" "$path_domain")
    first=0

    if [ "$path_domain" != "none" ]; then
      if [ -z "$verdict" ]; then
        verdict="$path_domain"
      elif [ "$verdict" != "$path_domain" ]; then
        verdict="ambiguous"
      fi
    fi
  done
  paths_json+="]"
  [ -z "$verdict" ] && verdict="ambiguous"

  printf '{"domain":"%s","paths":%s}\n' "$verdict" "$paths_json"
}

# Extracts fenced ```yaml blocks from docs/spec/assertions.md, filters by
# module (exact match) and, for security-sensitive agents, by the
# "security" tag, and prints one JSON object per matching assertion
# (comma-separated, ready to wrap in `[...]`). Building JSON inside awk --
# rather than handing tab/newline-separated rows back to the shell -- sidesteps
# bash `read`'s IFS-whitespace collapsing, which silently drops empty fields
# (e.g. a block with no `tags:` line) when the delimiter is a tab.
assertions_json() {
  local file="$1" module="$2" require_security="$3"
  awk -v mod="$module" -v want_sec="$require_security" '
    function jesc(s) {
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\\"", s)
      return s
    }
    function emit() {
      if (module == mod) {
        has_sec = (tags ~ /security/) ? 1 : 0
        if (want_sec == "0" || has_sec == 1) {
          if (count > 0) printf ","
          printf "{\"id\":\"%s\",\"module\":\"%s\",\"tags\":\"%s\",\"given\":\"%s\",\"when\":\"%s\",\"then\":\"%s\",\"and\":\"%s\"}", \
            jesc(id), jesc(module), jesc(tags), jesc(given), jesc(when), jesc(then_), jesc(and_)
          count++
        }
      }
    }
    BEGIN { count = 0 }
    /^```yaml$/ { inb=1; id=""; module=""; tags=""; given=""; when=""; then_=""; and_=""; next }
    /^```$/ { if (inb) { inb=0; emit() }; next }
    inb && /^id: */ { sub(/^id: */, ""); id=$0 }
    inb && /^module: */ { sub(/^module: */, ""); module=$0 }
    inb && /^tags: */ { sub(/^tags: */, ""); tags=$0 }
    inb && /^given: */ { sub(/^given: */, ""); given=$0 }
    inb && /^when: */ { sub(/^when: */, ""); when=$0 }
    inb && /^then: */ { sub(/^then: */, ""); then_=$0 }
    inb && /^and: */ { sub(/^and: */, ""); and_=$0 }
  ' "$file"
}

cmd_context() {
  local agent="" task="" module=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) agent="$2"; shift 2 ;;
      --task) task="$2"; shift 2 ;;
      --module) module="$2"; shift 2 ;;
      *) die "context: unknown argument $1" ;;
    esac
  done
  [ -n "$module" ] || die "context: --module is required"

  local root assertions_file require_security="0"
  root="$(repo_root)"
  assertions_file="${root}/docs/spec/assertions.md"
  if [ "$agent" = "security-reviewer" ] || [ "$agent" = "Security Reviewer" ]; then
    require_security="1"
  fi

  if [ ! -f "$assertions_file" ]; then
    printf '{"module":"%s","assertions":[]}\n' "$(json_escape "$module")"
    return 0
  fi

  local items
  items=$(assertions_json "$assertions_file" "$module" "$require_security")
  printf '{"module":"%s","assertions":[%s]}\n' "$(json_escape "$module")" "$items"
}

# Extracts each ```yaml task block from .llm/tasks.md as one record, fields
# joined with \x01 (not tab -- bash `read`'s IFS-whitespace collapsing drops
# empty fields on tab, same bug class fixed in assertions_json; \x01 isn't
# IFS-whitespace so it never collapses). One record per line:
# id\x01title\x01deps\x01criticality\x01specRefs\x01status\x01domain
tasks_records() {
  local file="$1"
  awk '
    function emit() { if (id != "") printf "%s\x01%s\x01%s\x01%s\x01%s\x01%s\x01%s\n", id, title, deps, criticality, specrefs, status, domain }
    /^```yaml$/ { inb=1; id=""; title=""; deps=""; criticality=""; specrefs=""; status=""; domain=""; next }
    /^```$/ { if (inb) { inb=0; emit() }; next }
    inb && /^id: */ { sub(/^id: */, ""); gsub(/^"|"$/, ""); id=$0 }
    inb && /^title: */ { sub(/^title: */, ""); gsub(/^"|"$/, ""); title=$0 }
    inb && /^deps: */ { sub(/^deps: */, ""); deps=$0 }
    inb && /^criticality: */ { sub(/^criticality: */, ""); criticality=$0 }
    inb && /^specRefs: */ { sub(/^specRefs: */, ""); specrefs=$0 }
    inb && /^status: */ { sub(/^status: */, ""); status=$0 }
    inb && /^domain: */ { sub(/^domain: */, ""); domain=$0 }
  ' "$file"
}

# Strips a YAML inline-list `[a, b]` or `["a", "b"]` down to a comma-joined,
# unquoted, space-trimmed scalar list (empty string if the list is empty).
strip_inline_list() {
  local raw="$1"
  raw="${raw#\[}"
  raw="${raw%\]}"
  printf '%s\n' "$raw" | tr ',' '\n' | sed -E 's/^ +//; s/ +$//; s/^"(.*)"$/\1/' | grep -v '^$' | paste -sd, - 2>/dev/null || true
}

cmd_tasks() {
  local sub="${1:-}"
  [ -n "$sub" ] || die "tasks: usage: workflow.sh tasks next"
  shift
  case "$sub" in
    next) cmd_tasks_next "$@" ;;
    *) die "tasks: unknown subcommand '${sub}' (expected 'next')" ;;
  esac
}

cmd_tasks_next() {
  local root tasks_file
  root="$(repo_root)"
  tasks_file="${root}/.llm/tasks.md"
  if [ ! -f "$tasks_file" ]; then
    printf '{"task":null,"reason":"no-tasks-file"}\n'
    return 0
  fi

  local records
  records=$(tasks_records "$tasks_file")
  if [ -z "$records" ]; then
    printf '{"task":null,"reason":"no-structured-tasks"}\n'
    return 0
  fi

  declare -A deps_of status_of title_of criticality_of specrefs_of domain_of
  local ids=() id title deps criticality specrefs status domain

  while IFS=$'\x01' read -r id title deps criticality specrefs status domain; do
    [ -z "$id" ] && continue
    ids+=("$id")
    deps_of["$id"]=$(strip_inline_list "$deps")
    status_of["$id"]="$status"
    title_of["$id"]="$title"
    criticality_of["$id"]="$criticality"
    specrefs_of["$id"]=$(strip_inline_list "$specrefs")
    domain_of["$id"]="$domain"
  done <<< "$records"

  # Cycle detection (DFS, 0=unvisited 1=visiting 2=done) over the whole graph
  # before picking a "next" task -- a cycle can silently strand a task behind
  # a dependency that will never be satisfiable.
  declare -A mark
  local cycle_path=""
  dfs_cycle() {
    local node="$1" path="$2" d dep
    case "${mark[$node]:-0}" in
      2) return 0 ;;
      1) cycle_path="${path} -> ${node}"; return 1 ;;
    esac
    mark["$node"]=1
    d="${deps_of[$node]:-}"
    if [ -n "$d" ]; then
      for dep in ${d//,/ }; do
        [ -n "${deps_of[$dep]+x}" ] || continue
        dfs_cycle "$dep" "${path} -> ${node}" || return 1
      done
    fi
    mark["$node"]=2
    return 0
  }
  for id in "${ids[@]}"; do
    if [ "${mark[$id]:-0}" = "0" ]; then
      dfs_cycle "$id" "" || { printf '{"task":null,"reason":"cycle-detected","cycle":"%s"}\n' "$(json_escape "${cycle_path#* -> }")"; return 0; }
    fi
  done

  # First task in file order that's not done and whose deps are all done.
  for id in "${ids[@]}"; do
    [ "${status_of[$id]}" = "done" ] && continue
    [ "${status_of[$id]}" = "blocked" ] && continue
    local all_deps_done=1 dep d
    d="${deps_of[$id]:-}"
    if [ -n "$d" ]; then
      for dep in ${d//,/ }; do
        if [ "${status_of[$dep]:-}" != "done" ]; then
          all_deps_done=0
          break
        fi
      done
    fi
    if [ "$all_deps_done" -eq 1 ]; then
      printf '{"task":{"id":"%s","title":"%s","deps":"%s","criticality":"%s","specRefs":"%s","status":"%s","domain":"%s"}}\n' \
        "$(json_escape "$id")" "$(json_escape "${title_of[$id]}")" "$(json_escape "${deps_of[$id]}")" \
        "$(json_escape "${criticality_of[$id]}")" "$(json_escape "${specrefs_of[$id]}")" \
        "$(json_escape "${status_of[$id]}")" "$(json_escape "${domain_of[$id]}")"
      return 0
    fi
  done

  printf '{"task":null,"reason":"none-ready"}\n'
}

main() {
  local cmd="${1:-}"
  [ -n "$cmd" ] || die "usage: workflow.sh <init|next|gate|complete|classify|context|tasks> [options]"
  shift
  case "$cmd" in
    init) cmd_init "$@" ;;
    next) cmd_next "$@" ;;
    gate) cmd_gate "$@" ;;
    complete) cmd_complete "$@" ;;
    classify) cmd_classify "$@" ;;
    tasks) cmd_tasks "$@" ;;
    context) cmd_context "$@" ;;
    *) die "unknown command: ${cmd}" ;;
  esac
}

main "$@"
