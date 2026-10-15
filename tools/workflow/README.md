# Workflow Engine CLI

Two implementations of the same contract — `workflow.ps1` (requires the `powershell-yaml`
module: `Install-Module powershell-yaml`) and `workflow.sh` (bash, with a hand-rolled
extractor in `lib/pipeline.sh` scoped to exactly what `workflow/pipelines.yml` needs — not
a general YAML parser). Pick whichever matches your shell; both read the same
`workflow/pipelines.yml` and write the same state-file format, so a task started with one
can be resumed with the other.

All commands print one JSON object to stdout. Errors print `{"error": "..."}` and exit
non-zero.

## Commands

### `init --task <id> --pipeline <software|infrastructure> [--slug <slug>]`

Resolves the working branch (create / use / ask, per `tech-lead.md` Step 2b — see
`workflow/README.md`), writes the state-file skeleton, and returns the first phase:

```json
{"phase": "SPEC_REVIEW_GATE", "agent": "Spec Reviewer", "branch": "task/42-foo", "stateFile": "..."}
```

If the current branch doesn't resolve deterministically (wrong task's branch, or an
unrecognized branch that isn't an integration branch), it instead returns an `ask` payload
and exits `2` — the conductor must resolve this with the human before retrying:

```json
{"action": "ask", "reason": "wrong-task-branch", "currentBranch": "task/41-bar"}
```

`--slug` overrides the branch slug derived from `--task` when creating a new branch.

### `next [--pipeline <name>]`

Returns the phase(s) to run next. Normally one; two when the current stage has parallel
phases (e.g. `AUDIT` + `SECURITY`) and not all of them have gated clean yet:

```json
{"phases": [{"phase": "RED", "agent": "Tester"}], "contextRefs": ["<stateFile path>"]}
```

A `SPEC_REVIEW_GATE`-style conditional phase is skipped automatically (and `next` returns
the phase after it) when its `skipWhen` condition in `pipelines.yml` already holds — see
`workflow/README.md`. Once the pipeline is finished: `{"phases": [], "status": "complete", ...}`.

`--pipeline` is required only when both the software and infrastructure pipelines have an
in-progress state file at once; otherwise the engine infers it.

### `gate --phase <id> --verdict <value> [--reason <value> ...] [--actual <n> --target <n>] [--pipeline <name>]`

Applies the deterministic gate logic and returns one of `ADVANCE | PAUSE | FAIL`:

```json
{"result": "ADVANCE", "nextPhase": "GREEN", "onPass": null}
```

- `--actual`/`--target`: if given and `actual < target`, the result is always `FAIL` —
  **regardless of `--verdict`**. A threshold check cannot be talked past by a verdict string.
- `--reason`: each value must be one of the fixed set documented in `workflow/README.md`
  (`spec-gap`, `blocked`, `safety-critical-survivor`, `formal-counterexample`,
  `critical-finding`, `fail`). Any other value is rejected outright. If a reason matches the
  phase's `pauseWhen` list, the result is `PAUSE` and the reason is recorded under
  `## Blocking Issues` in the state file.
- On `ADVANCE` past a parallel stage (every phase in the group has now gated clean), the
  group's `## Blocking Issues` entries are cleared and `Status` returns to `in-progress`.
- `onPass` surfaces a declared side effect (currently only `open-pr`) for the conductor to
  perform — the engine itself never touches GitHub.

### `complete --task <id> [--pipeline <name>]`

Only succeeds once the pipeline has reached its last phase (state file's `Current Phase` is
the sentinel `DONE`); otherwise it refuses with an error naming the phase still outstanding.
Marks the task's checkbox in `.llm/tasks.md` (`- [ ] <id> ...` → `- [x] <id> ...`, a
best-effort match against today's unstructured task list — this becomes exact once
structured task records land) and sets the state file's `Status` to `complete`.

### `classify [--task <id>] [--path <p> ...]`

Replaces the hand-written Frontend/Backend/Infrastructure prose tables that used to live in
`tech-lead.md` Step 2 and `planner.md`'s Project Type Detection section. Returns:

```json
{"domain": "backend", "paths": [{"path": "docs/spec/interfaces/auth-operations.md", "domain": "backend"}]}
```

`domain` is `frontend`, `backend`, `infrastructure`, or `ambiguous`. Resolution is glob-based
against the `classify:` block in `.tech-decisions.yml` (`frontend:`, `backend:`,
`infrastructure:` — each an inline list of path globs; see the block
`tools/ai-bootstrap/bootstrap-ai-repo.ps1`/`.sh` generate). `--path` can be given directly
(repeatable); `--task <id>` instead scans that task's block in `.llm/tasks.md` for
`docs/spec/...`-looking references and classifies those — a best-effort text scan today,
exact once structured `specRefs` fields exist.

`ambiguous` is returned — never an error — when: no path resolves at all, a path matches
more than one domain's globs, two resolved paths disagree, or `.tech-decisions.yml` doesn't
exist yet. This is deliberate: `ambiguous` is the one case the old prose got right (ask the
human once) and the only case that should still reach one.

## State file

Both engines read/write a fixed machine-managed header (`**Task:**`, `**Pipeline:**`,
`**Branch:**`, `**Current Phase:**`, `**Phases Done:**`, `**Status:**`) plus
`## Existing Work` and `## Blocking Issues` sections they append to. Everything else in the
file — `## Standards`, `## Toolchain`, `## Relevant Assertions`, etc. — is written by the
conductor/agent, never by this engine; `init` writes those sections as empty placeholders
and leaves them alone afterward.

## Testing

`test/test-workflow.sh` and `test/test-workflow.ps1` are self-contained, dependency-free
(no Pester, no bats) — they actually run the engine against disposable scratch git repos,
mirroring the convention in `tools/ai-bootstrap/test/`. Run them directly:

```bash
bash tools/workflow/test/test-workflow.sh
pwsh tools/workflow/test/test-workflow.ps1
```

Both must report 0 failures before any change to `workflow.ps1`, `workflow.sh`, or either
`lib/` file is considered done — they're kept in strict scenario-for-scenario parity.
