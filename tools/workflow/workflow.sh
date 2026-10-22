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

  # Resuming an already-initialized task: never re-run state_init, which
  # would unconditionally truncate the file and reset Current Phase, Phases
  # Done, Tier, Existing Work, and Blocking Issues back to a blank slate --
  # exactly the state Conductor Step 1 calls `init` to preserve on resume.
  if [ -f "$state_file" ] && [ "$(state_get_field "$state_file" "Task")" = "$task" ]; then
    local resume_phase resume_agent
    resume_phase=$(state_get_field "$state_file" "Current Phase")
    if [ "$resume_phase" = "DONE" ]; then
      resume_agent=""
    else
      resume_agent=$(pl_phase_scalar "$(pl_phase_block "$block" "$resume_phase")" agent)
    fi
    printf '{"phase":"%s","agent":"%s","branch":"%s","stateFile":"%s"}\n' \
      "$(json_escape "$resume_phase")" "$(json_escape "$resume_agent")" "$(json_escape "$branch")" "$(json_escape "$state_file")"
    return 0
  fi

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

# Given a phase (already marked done by the caller) and its parallel
# siblings, checks whether the whole group has now gated clean and, if so,
# advances Current Phase past it (clearing Phases Done / Blocking Issues,
# finding the next phase order-independently by highest canonical index).
# Prints "1|<nextId>|<onPassValue>" if it advanced, "0||" otherwise.
advance_past_group_if_complete() {
  local state_file="$1" block="$2" phase="$3" parallel="$4" phase_block="$5"
  local done_list group_complete=1 id
  done_list=$(state_phases_done_get "$state_file")
  for id in "$phase" $parallel; do
    case " $done_list " in
      *" $id "*) : ;;
      *) group_complete=0 ;;
    esac
  done
  if [ "$group_complete" -eq 1 ]; then
    local ids=() next_id="" max_idx=-1 i g onpass_raw
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
    onpass_raw=$(pl_phase_scalar "$phase_block" onPass)
    echo "1|${next_id}|${onpass_raw}"
  else
    echo "0||"
  fi
}

cmd_next_inner() {
  local root="$1" pfile="$2" name="$3" state_file="$4"
  local block current_phase phase_block parallel done_list phases_json first=1 id agent tier

  block=$(pl_pipeline_block "$pfile" "$name")
  current_phase=$(state_get_field "$state_file" "Current Phase")

  if [ "$current_phase" = "DONE" ]; then
    printf '{"phases":[],"status":"complete","contextRefs":["%s"]}\n' "$(json_escape "$state_file")"
    return 0
  fi

  phase_block=$(pl_phase_block "$block" "$current_phase")
  parallel=$(pl_phase_list "$phase_block" parallelWith)
  tier=$(state_get_field "$state_file" "Tier")

  # Unconditional tier-based skip: mark any not-yet-done member of this
  # stage as done without invoking its agent, if the recorded tier is in
  # its skipOnTier list (e.g. AUDIT/DOCUMENT under tier: minimal).
  if [ -n "$tier" ]; then
    done_list=$(state_phases_done_get "$state_file")
    for id in "$current_phase" $parallel; do
      case " $done_list " in
        *" $id "*) continue ;;
      esac
      local id_skip
      id_skip=$(pl_phase_list "$(pl_phase_block "$block" "$id")" skipOnTier)
      if pl_list_contains "$id_skip" "$tier"; then
        state_phases_done_add "$state_file" "$id"
        state_append_existing_work "$state_file" "${id}: skipped (tier: ${tier}, skipOnTier) -- no agent dispatched, no evidence produced for this phase"
      fi
    done
  fi

  # If that skip completed the whole stage, advance and re-resolve from the
  # new Current Phase (handles e.g. a parallel pair where only one member
  # was tier-skipped and the other already gated clean earlier).
  local adv_result group_complete next_id onpass_raw
  adv_result=$(advance_past_group_if_complete "$state_file" "$block" "$current_phase" "$parallel" "$phase_block")
  IFS='|' read -r group_complete next_id onpass_raw <<< "$adv_result"
  if [ "$group_complete" = "1" ]; then
    cmd_next_inner "$root" "$pfile" "$name" "$state_file"
    return 0
  fi

  done_list=$(state_phases_done_get "$state_file")
  phases_json="["
  for id in "$current_phase" $parallel; do
    case " $done_list " in
      *" $id "*) continue ;;
    esac
    local id_phase_block isolation_mode
    id_phase_block=$(pl_phase_block "$block" "$id")
    agent=$(pl_phase_scalar "$id_phase_block" agent)
    isolation_mode=$(resolve_and_cache_isolation "$state_file" "$root" "$id_phase_block" "$id")
    [ "$first" -eq 1 ] || phases_json+=","
    phases_json+=$(printf '{"phase":"%s","agent":"%s","isolation":"%s"}' "$(json_escape "$id")" "$(json_escape "$agent")" "$(json_escape "$isolation_mode")")
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
      if pl_list_contains "$pausewhen" "$r"; then
        result="PAUSE"
        blocking_reason="$r"
        break
      fi
    done
  fi

  state_append_existing_work "$state_file" "${phase}: verdict=${verdict} result=${result}$( [ -n "$blocking_reason" ] && printf ' (%s)' "$blocking_reason" )"

  local next_phase="null" onpass="null"
  if [ "$result" = "ADVANCE" ]; then
    local parallel=$(pl_phase_list "$phase_block" parallelWith)
    state_phases_done_add "$state_file" "$phase"
    local adv_result next_id group_complete onpass_raw
    adv_result=$(advance_past_group_if_complete "$state_file" "$block" "$phase" "$parallel" "$phase_block")
    IFS='|' read -r group_complete next_id onpass_raw <<< "$adv_result"
    if [ "$group_complete" = "1" ]; then
      [ -n "$next_id" ] && next_phase="\"${next_id}\""
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
  raw=$(printf '%s' "$raw" | sed -E 's/ +#.*$//; s/ +$//')
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

# Reads the top-level (not nested) `risk_paths:` inline list from
# .tech-decisions.yml. Missing file or key -> empty list.
risk_paths_list() {
  local file="$1"
  [ -f "$file" ] || return 0
  local raw
  raw=$({ grep -m1 -E "^risk_paths:" "$file" || true; } | sed -E "s/^risk_paths: *//")
  raw=$(printf '%s' "$raw" | sed -E 's/ +#.*$//; s/ +$//')
  raw="${raw#\[}"
  raw="${raw%\]}"
  [ -z "$raw" ] && return 0
  printf '%s\n' "$raw" | tr ',' '\n' | sed -E 's/^ +//; s/ +$//' | sed -E 's/^"(.*)"$/\1/'
}

# Reads one override value under .tech-decisions.yml's top-level
# isolation: -> overrides: -> <phase>: (one level deeper than classify:'s
# domain keys -- see workflow/isolation.md section 5.2). Missing file,
# block, or phase -> empty (caller falls back to the pipelines.yml default).
tech_isolation_override() {
  local file="$1" phase_id="$2"
  [ -f "$file" ] || return 0
  local isolation_block overrides_block
  isolation_block=$(awk '
    /^isolation:/ { inb=1; next }
    inb && /^[A-Za-z]/ { exit }
    inb { print }
  ' "$file")
  overrides_block=$(printf '%s\n' "$isolation_block" | awk '
    /^  overrides:/ { ino=1; next }
    ino && /^  [A-Za-z]/ { exit }
    ino { print }
  ')
  printf '%s\n' "$overrides_block" | { grep -m1 -E "^    ${phase_id}:" || true; } | sed -E "s/^    ${phase_id}: *//"
}

# Resolves the repo-level isolation baseline for one phase: pipelines.yml's
# shipped default, after .tech-decisions.yml's isolation.overrides (which
# can move a phase either direction -- see workflow/isolation.md section
# 5.2). Prints "<mode>|<source>" (source is "repo override" or "repo
# default"), always freshly computed -- never reads the state file's cache.
resolve_isolation_baseline() {
  local phase_block="$1" tech_file="$2" phase_id="$3"
  local pipeline_default override
  pipeline_default=$(pl_phase_isolation "$phase_block")
  override=$(tech_isolation_override "$tech_file" "$phase_id")
  if [ -n "$override" ]; then
    echo "${override}|repo override"
  else
    echo "${pipeline_default}|repo default"
  fi
}

# Resolves and returns the EFFECTIVE isolation mode for one phase as next
# sees it: the state file's cached record if one already exists (a prior
# repo-default resolution, or a task override), otherwise the repo baseline
# freshly computed and recorded now (source "repo default"/"repo override").
# Never recomputes once cached, so a later .tech-decisions.yml edit does not
# retroactively change a phase already resolved for this task.
resolve_and_cache_isolation() {
  local state_file="$1" root="$2" phase_block="$3" phase_id="$4"
  local cached mode
  cached=$(state_isolation_get "$state_file" "$phase_id")
  if [ -n "$cached" ]; then
    echo "$cached" | awk '{print $1}'
    return 0
  fi
  local baseline mode_source
  baseline=$(resolve_isolation_baseline "$phase_block" "${root}/.tech-decisions.yml" "$phase_id")
  mode="${baseline%%|*}"
  mode_source="${baseline#*|}"
  state_isolation_set "$state_file" "$phase_id" "$mode" "$mode_source"
  echo "$mode"
}

cmd_tier() {
  local files_changed="" override="" pipeline=""
  local paths=() untested=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --files-changed) files_changed="$2"; shift 2 ;;
      --path) paths+=("$2"); shift 2 ;;
      --untested-module) untested+=("$2"); shift 2 ;;
      --override) override="$2"; shift 2 ;;
      --pipeline) pipeline="$2"; shift 2 ;;
      *) die "tier: unknown argument $1" ;;
    esac
  done
  [ -n "$files_changed" ] || die "tier: --files-changed is required"

  local root tech_file risk_globs p risk_hit=0
  root="$(repo_root)"
  tech_file="${root}/.tech-decisions.yml"
  risk_globs=$(risk_paths_list "$tech_file")
  for p in "${paths[@]:-}"; do
    [ -z "$p" ] && continue
    if path_matches_domain "$p" "$risk_globs"; then
      risk_hit=1
    fi
  done

  local natural="" reason=""
  if [ "$risk_hit" -eq 1 ]; then
    natural="elevated"
    reason="touches a risk_paths-tagged path"
  elif [ "$files_changed" -gt 15 ] 2>/dev/null; then
    natural="elevated"
    reason="${files_changed} files changed (>15)"
  elif [ "${#untested[@]}" -gt 0 ]; then
    natural="elevated"
    reason="no existing tests for: ${untested[*]}"
  elif [ "$files_changed" -le 3 ] 2>/dev/null; then
    natural="minimal"
    reason="${files_changed} files changed (<=3), no risk paths, tests exist for every touched module"
  else
    natural="standard"
    reason="${files_changed} files changed, no risk paths or untested modules triggering elevation"
  fi

  local final="$natural" overridden="false" rejected="null"
  if [ -n "$override" ]; then
    if [ "$risk_hit" -eq 1 ] && [ "$override" != "elevated" ]; then
      rejected="\"cannot override down from elevated: a risk_paths match is a hard rule\""
    else
      final="$override"
      overridden="true"
      reason="human override from ${natural} (${reason})"
    fi
  fi

  local root2 resolved name state_file
  if [ -n "$pipeline" ]; then
    resolved=$(resolve_named_pipeline "$pipeline")
  else
    resolved=$(resolve_active_pipeline)
  fi
  name=$(echo "$resolved" | cut -d' ' -f1)
  state_file=$(echo "$resolved" | cut -d' ' -f2-)
  if [ -f "$state_file" ]; then
    state_set_field "$state_file" "Tier" "$final"
    state_set_field "$state_file" "Tier Reason" "$reason"
  fi

  printf '{"tier":"%s","reason":"%s","overridden":%s,"rejectedOverride":%s}\n' \
    "$(json_escape "$final")" "$(json_escape "$reason")" "$overridden" "$rejected"
}

cmd_isolation() {
  local phase="" override="" pipeline=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --phase) phase="$2"; shift 2 ;;
      --override) override="$2"; shift 2 ;;
      --pipeline) pipeline="$2"; shift 2 ;;
      *) die "isolation: unknown argument $1" ;;
    esac
  done
  [ -n "$phase" ] || die "isolation: --phase is required"
  [ -n "$override" ] || die "isolation: --override is required"
  case "$override" in
    container|direct) : ;;
    *) die "isolation: --override must be 'container' or 'direct'" ;;
  esac

  local root pfile resolved name state_file block phase_block
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

  # Always resolved fresh against the repo baseline -- never against
  # whatever next may have already cached in the state file -- so this
  # command's refusal rule can't be bypassed by whatever happens to be
  # cached from an earlier `next` call.
  local baseline baseline_mode baseline_source
  baseline=$(resolve_isolation_baseline "$phase_block" "${root}/.tech-decisions.yml" "$phase")
  baseline_mode="${baseline%%|*}"
  baseline_source="${baseline#*|}"

  local final="$baseline_mode" overridden="false" rejected="null"
  if [ "$override" = "$baseline_mode" ]; then
    : # requesting what's already in effect -- no-op
  elif [ "$override" = "container" ] && [ "$baseline_mode" = "direct" ]; then
    final="container"
    overridden="true"
    state_isolation_set "$state_file" "$phase" "container" "task override, strengthened from ${baseline_source}: direct"
  else
    rejected="\"cannot downgrade ${phase} below repo policy (container)\""
  fi

  printf '{"phase":"%s","isolation":"%s","overridden":%s,"rejectedOverride":%s}\n' \
    "$(json_escape "$phase")" "$(json_escape "$final")" "$overridden" "$rejected"
}

# Finds the merge-base between HEAD and the first existing candidate
# integration branch (main, master, develop, in that order). Prints empty
# if none exist -- the caller treats that as "no base, no diff" rather than
# an error (a single-branch repo, or a phase run before any integration
# branch was created).
isolation_diff_base() {
  local root="$1" cand base=""
  for cand in main master develop; do
    if (cd "$root" && git show-ref --verify --quiet "refs/heads/${cand}") 2>/dev/null; then
      base=$(cd "$root" && git merge-base HEAD "$cand" 2>/dev/null || true)
      [ -n "$base" ] && break
    fi
  done
  echo "$base"
}

# Resolves the active toolchain name for this repo via .tech-decisions.yml's
# toolchains.detect (first if_exists glob -- possibly "a|b" alternation --
# that matches a direct child of the repo root wins, checked in file
# order) else toolchains.default. Empty if .tech-decisions.yml is absent,
# its toolchains: block is missing, or neither resolves (including an
# explicit YAML `default: null`). See workflow/isolation.md section 12.
isolation_resolve_toolchain() {
  local root="$1" tech_file="${root}/.tech-decisions.yml"
  [ -f "$tech_file" ] || { echo ""; return 0; }

  local toolchains_block
  toolchains_block=$(awk '
    /^toolchains:/ { inb = 1; next }
    inb && /^[A-Za-z]/ { exit }
    inb { print }
  ' "$tech_file")
  [ -n "$toolchains_block" ] || { echo ""; return 0; }

  local detect_block
  detect_block=$(printf '%s\n' "$toolchains_block" | awk '
    /^  detect:/ { ind = 1; next }
    ind && /^  [A-Za-z]/ { exit }
    ind { print }
  ')

  local globs=() names=() cur_glob="" cur_name="" line
  while IFS= read -r line; do
    case "$line" in
      "    - if_exists:"*)
        [ -n "$cur_glob" ] && { globs+=("$cur_glob"); names+=("$cur_name"); }
        cur_glob=$(printf '%s' "$line" | sed -E 's/^    - if_exists: *//; s/ +#.*$//; s/^"(.*)"$/\1/')
        cur_name=""
        ;;
      "      toolchain:"*)
        cur_name=$(printf '%s' "$line" | sed -E 's/^      toolchain: *//; s/ +#.*$//; s/ +$//')
        ;;
    esac
  done <<< "$detect_block"
  [ -n "$cur_glob" ] && { globs+=("$cur_glob"); names+=("$cur_name"); }

  local i alt alts
  for i in "${!globs[@]}"; do
    IFS='|' read -ra alts <<< "${globs[$i]}"
    for alt in "${alts[@]}"; do
      if compgen -G "${root}/${alt}" >/dev/null 2>&1; then
        echo "${names[$i]}"
        return 0
      fi
    done
  done

  local default_val
  default_val=$(printf '%s\n' "$toolchains_block" | { grep -m1 -E "^  default:" || true; } | sed -E 's/^  default: *//; s/ +#.*$//; s/ +$//')
  [ "$default_val" = "null" ] && default_val=""
  echo "$default_val"
}

# Hardcoded toolchain-name -> default base image table -- a deliberately
# narrow v1 choice (same reasoning as section 6's hardcoded timeout/quota
# defaults): not configurable yet, add a .tech-decisions.yml override only
# once a real repo actually needs one. An unresolved/unrecognized
# toolchain falls back to a generic minimal image rather than failing --
# image resolution should never block on an unknown toolchain name.
isolation_default_image() {
  case "$1" in
    rust) echo "rust:1-slim" ;;
    dotnet) echo "mcr.microsoft.com/dotnet/sdk:8.0" ;;
    typescript|javascript) echo "node:20-slim" ;;
    python) echo "python:3.12-slim" ;;
    *) echo "debian:12-slim" ;;
  esac
}

# Resolves the container image for a containerized phase: the target
# repo's own .devcontainer/devcontainer.json ("image" field directly, or
# "build.dockerfile"/"build.context" if it builds one instead), falling
# back to a toolchain-derived default image when no devcontainer.json
# exists or it names neither. See workflow/isolation.md section 12.
#
# Prints one of:
#   image:<reference>              -- pull/run this image directly
#   build:<dockerfile>:<context>   -- build from this Dockerfile first
#
# Does not pull or build anything itself -- that's the (not yet built)
# spawn step's job; this is resolution only.
#
# Documented limitation, not assumed away: devcontainer.json is read with a
# minimal regex extraction, not a real JSON(C) parser -- a comment
# interleaved with the "image"/"build" keys in an unusual way could defeat
# it. Matches this engine's existing "not a general parser" posture for
# .tech-decisions.yml/pipelines.yml.
isolation_resolve_image() {
  local root="$1" dc_file="${root}/.devcontainer/devcontainer.json"

  if [ -f "$dc_file" ]; then
    local image
    image=$(grep -oE '"image"[[:space:]]*:[[:space:]]*"[^"]*"' "$dc_file" | head -1 | sed -E 's/^"image"[[:space:]]*:[[:space:]]*"//; s/"$//')
    if [ -n "$image" ]; then
      echo "image:${image}"
      return 0
    fi

    local dockerfile context
    dockerfile=$(grep -oE '"dockerfile"[[:space:]]*:[[:space:]]*"[^"]*"' "$dc_file" | head -1 | sed -E 's/^"dockerfile"[[:space:]]*:[[:space:]]*"//; s/"$//')
    if [ -n "$dockerfile" ]; then
      context=$(grep -oE '"context"[[:space:]]*:[[:space:]]*"[^"]*"' "$dc_file" | head -1 | sed -E 's/^"context"[[:space:]]*:[[:space:]]*"//; s/"$//')
      [ -n "$context" ] || context="."
      echo "build:${dockerfile}:${context}"
      return 0
    fi
  fi

  local toolchain image
  toolchain=$(isolation_resolve_toolchain "$root")
  image=$(isolation_default_image "$toolchain")
  echo "image:${image}"
}

# Materializes a containerized phase's input files under
# .llm/isolation/<slug>/<phase>/input/ -- prompt.md (the same assembled
# content a direct Task-tool dispatch would otherwise inline, written to a
# file instead) and task.json (structured metadata for the container
# entrypoint, including the resolved image/build spec from
# isolation_resolve_image -- section 12). Prints the input directory path.
# See workflow/isolation.md section 6.
#
# Scope note: Standards/Toolchain/Context are written verbatim from the
# state file, not per-agent-filtered the way conductor.md's own prompt
# template describes for a direct dispatch -- that filtering is a
# refinement for later, not a security requirement (Context content isn't
# secret), and this keeps the materialize/read-back mechanism itself the
# thing being built here. "## Task" is the bare task id, not the full
# title/description a direct dispatch gets from the Conductor's own
# knowledge of .llm/tasks.md -- same reasoning, documented simplification.
isolation_materialize_input() {
  local root="$1" task="$2" pipeline="$3" branch="$4" phase_id="$5" agent="$6" state_file="$7" slug="$8"
  local dir="${root}/.llm/isolation/${slug}/${phase_id}/input"
  mkdir -p "$dir"

  local standards toolchain context existing_work
  standards=$(state_get_section "$state_file" "Standards")
  toolchain=$(state_get_section "$state_file" "Toolchain")
  context=$(state_get_section "$state_file" "Context")
  existing_work=$(state_get_section "$state_file" "Existing Work")

  # Matches conductor.md's own template: RED/GREEN (and the infra analogue,
  # IMPLEMENT) get no Diff section -- there's nothing meaningful to diff
  # against before the first code-writing phase has run. REFACTOR/AUDIT do.
  local diff_block=""
  case "$phase_id" in
    REFACTOR|AUDIT)
      local base diff_text
      base=$(isolation_diff_base "$root")
      if [ -n "$base" ]; then
        diff_text=$(cd "$root" && git diff "$base" 2>/dev/null || true)
        diff_block=$'\n## Diff\n'"${diff_text}"$'\n'
      fi
      ;;
  esac

  {
    printf '## Working Directory\nWork in the current git workspace.\n\n'
    printf '## Task\n#%s\n\n' "$task"
    printf '## Standards\n%s\n\n' "$standards"
    printf '## Toolchain\n%s\n\n' "$toolchain"
    printf '## Context\n%s\n\n' "$context"
    printf '## Existing Work\n%s\n' "$existing_work"
    [ -n "$diff_block" ] && printf '%s' "$diff_block"
  } > "${dir}/prompt.md"

  local image
  image=$(isolation_resolve_image "$root")

  printf '{"id":"%s","title":"%s","pipeline":"%s","phase":"%s","branch":"%s","agent":"%s","image":"%s"}\n' \
    "$(json_escape "$task")" "$(json_escape "$task")" "$(json_escape "$pipeline")" \
    "$(json_escape "$phase_id")" "$(json_escape "$branch")" "$(json_escape "$agent")" \
    "$(json_escape "$image")" \
    > "${dir}/task.json"

  echo "$dir"
}

cmd_run_isolated() {
  local phase="" pipeline=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --phase) phase="$2"; shift 2 ;;
      --pipeline) pipeline="$2"; shift 2 ;;
      *) die "run-isolated: unknown argument $1" ;;
    esac
  done
  [ -n "$phase" ] || die "run-isolated: --phase is required"

  local root pfile resolved name state_file block phase_block
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

  local isolation_mode
  isolation_mode=$(resolve_and_cache_isolation "$state_file" "$root" "$phase_block" "$phase")
  [ "$isolation_mode" = "container" ] || die "run-isolated: phase ${phase} is not isolated (resolved mode: ${isolation_mode})"

  local task pipeline_val branch agent prefix slug
  task=$(state_get_field "$state_file" "Task")
  pipeline_val=$(state_get_field "$state_file" "Pipeline")
  branch=$(state_get_field "$state_file" "Branch")
  agent=$(pl_phase_scalar "$phase_block" agent)
  prefix=$(pl_scalar "$block" branchPrefix)
  slug="${branch#"$prefix"}"

  local input_dir
  input_dir=$(isolation_materialize_input "$root" "$task" "$pipeline_val" "$branch" "$phase" "$agent" "$state_file" "$slug")

  local verdict_file="${root}/.llm/isolation/${slug}/${phase}/output/verdict.json"
  if [ -f "$verdict_file" ]; then
    cat "$verdict_file"
    return 0
  fi

  die "run-isolated: container spawn is not yet implemented (input materialized at ${input_dir}; workflow/isolation.md section 3's container lifecycle remains to be built)"
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
          printf "{\"id\":\"%s\",\"module\":\"%s\",\"tags\":\"%s\",\"given\":\"%s\",\"when\":\"%s\",\"then\":\"%s\",\"and\":\"%s\",\"requirementRef\":\"%s\"}", \
            jesc(id), jesc(module), jesc(tags), jesc(given), jesc(when), jesc(then_), jesc(and_), jesc(reqref)
          count++
        }
      }
    }
    BEGIN { count = 0 }
    /^```yaml$/ { inb=1; id=""; module=""; tags=""; given=""; when=""; then_=""; and_=""; reqref=""; next }
    /^```$/ { if (inb) { inb=0; emit() }; next }
    inb && /^id: */ { sub(/^id: */, ""); id=$0 }
    inb && /^module: */ { sub(/^module: */, ""); module=$0 }
    inb && /^tags: */ { sub(/^tags: */, ""); tags=$0 }
    inb && /^given: */ { sub(/^given: */, ""); given=$0 }
    inb && /^when: */ { sub(/^when: */, ""); when=$0 }
    inb && /^then: */ { sub(/^then: */, ""); then_=$0 }
    inb && /^and: */ { sub(/^and: */, ""); and_=$0 }
    inb && /^requirementRef: */ { sub(/^requirementRef: */, ""); reqref=$0 }
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
  [ -n "$cmd" ] || die "usage: workflow.sh <init|next|gate|complete|classify|context|tasks|tier|isolation|run-isolated> [options]"
  shift
  case "$cmd" in
    init) cmd_init "$@" ;;
    next) cmd_next "$@" ;;
    gate) cmd_gate "$@" ;;
    complete) cmd_complete "$@" ;;
    classify) cmd_classify "$@" ;;
    tasks) cmd_tasks "$@" ;;
    context) cmd_context "$@" ;;
    tier) cmd_tier "$@" ;;
    isolation) cmd_isolation "$@" ;;
    run-isolated) cmd_run_isolated "$@" ;;
    *) die "unknown command: ${cmd}" ;;
  esac
}

main "$@"
