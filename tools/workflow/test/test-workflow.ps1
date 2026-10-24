#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Self-contained, dependency-free end-to-end test harness for
    tools/workflow/workflow.ps1 (issue #55).
.DESCRIPTION
    No Pester, no external test-framework dependency -- this repo validates
    its shell/PowerShell tooling by actually running it against a scratch
    git repo, not by reading the script or mocking its dependencies.
    Mirrors test-workflow.sh scenario-for-scenario for contract parity.
.EXAMPLE
    pwsh ./tools/workflow/test/test-workflow.ps1
#>

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
$WorkflowPs1 = Join-Path $RepoRoot "tools/workflow/workflow.ps1"
$PipelinesYml = Join-Path $RepoRoot "workflow/pipelines.yml"
$LibDir = Join-Path $RepoRoot "tools/workflow/lib"

$script:PassCount = 0
$script:FailCount = 0
$script:FailedNames = @()

function Pass([string]$Name) {
    $script:PassCount++
    Write-Host "  PASS: $Name"
}

function Fail([string]$Name, [string]$Detail) {
    $script:FailCount++
    $script:FailedNames += $Name
    Write-Host "  FAIL: $Name -- $Detail"
}

function Assert-Eq([string]$Name, $Expected, $Actual) {
    if ("$Expected" -eq "$Actual") { Pass $Name } else { Fail $Name "expected [$Expected], got [$Actual]" }
}

function Assert-Contains([string]$Name, [string]$Haystack, [string]$Needle) {
    # Plain substring check -- `-like`/`-match` give `[`/`]` wildcard/regex
    # meaning we don't want here (state-file markers like "[None]" are literal).
    if ($Haystack.Contains($Needle)) { Pass $Name } else { Fail $Name "expected output to contain [$Needle], got [$Haystack]" }
}

function Get-JsonField([string]$Json, [string]$Field) {
    $m = [regex]::Match($Json, "`"$Field`":`"([^`"]*)`"")
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($Json, "`"$Field`":([^,}]*)")
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function New-Scratch([string]$Dir) {
    if (Test-Path $Dir) { Remove-Item -Recurse -Force $Dir }
    New-Item -ItemType Directory -Path "$Dir/workflow", "$Dir/tools/workflow", "$Dir/docs/spec", "$Dir/.llm/spec-review" -Force | Out-Null
    Copy-Item $PipelinesYml "$Dir/workflow/pipelines.yml"
    Copy-Item -Recurse $LibDir "$Dir/tools/workflow/lib"
    Copy-Item $WorkflowPs1 "$Dir/tools/workflow/workflow.ps1"
    Push-Location $Dir
    try {
        git init -q
        git config user.email test@test.com
        git config user.name test
        "initial" | Set-Content README.md
        git add -A
        git commit -q -m init
        git branch -m main 2>$null
    } finally {
        Pop-Location
    }
}

function Invoke-Wf([string]$Dir, [string[]]$WfArgs) {
    $script = Join-Path $Dir "tools/workflow/workflow.ps1"
    Push-Location $Dir
    try {
        $out = & $script @WfArgs 2>&1
        return [PSCustomObject]@{ Output = ($out -join "`n"); ExitCode = $LASTEXITCODE }
    } finally {
        Pop-Location
    }
}

Write-Host "=== tools/workflow/test/test-workflow.ps1 ==="
Write-Host ""

# --- Tier 1: happy path -----------------------------------------------------

Write-Host "Tier 1 - happy path"

$scr = Join-Path $env:TEMP "wf-ps-t1-$(Get-Random)"
New-Scratch $scr

$r = Invoke-Wf $scr @("init", "--task", "t1", "--pipeline", "software")
Assert-Eq "01 init creates branch and returns first phase" "SPEC_REVIEW_GATE" (Get-JsonField $r.Output "phase")
Push-Location $scr; $branch = (git branch --show-current); Pop-Location
Assert-Eq "02 init creates task/ branch from main" "task/t1" $branch
Assert-Eq "03 init returns first phase's agent name" "Spec Reviewer" (Get-JsonField $r.Output "agent")

$r = Invoke-Wf $scr @("init", "--task", "t1", "--pipeline", "software")
Assert-Eq "04 re-init on same task/branch reuses it (use)" "task/t1" (Get-JsonField $r.Output "branch")

Invoke-Wf $scr @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
$r = Invoke-Wf $scr @("next")
Assert-Contains "05 RED -> GREEN -> REFACTOR sequential advance (RED next)" $r.Output '"phase":"RED"'
Invoke-Wf $scr @("gate", "--phase", "RED", "--verdict", "done") | Out-Null
$r = Invoke-Wf $scr @("next")
Assert-Contains "06 sequential advance (GREEN next)" $r.Output '"phase":"GREEN"'
Invoke-Wf $scr @("gate", "--phase", "GREEN", "--verdict", "done") | Out-Null
$r = Invoke-Wf $scr @("next")
Assert-Contains "07 sequential advance (REFACTOR next)" $r.Output '"phase":"REFACTOR"'
Invoke-Wf $scr @("gate", "--phase", "REFACTOR", "--verdict", "CLEAN") | Out-Null

$r = Invoke-Wf $scr @("next")
Assert-Contains "08 parallel stage returns both AUDIT and SECURITY" $r.Output '"phase":"AUDIT"'
Assert-Contains "09 parallel stage returns both AUDIT and SECURITY (cont.)" $r.Output '"phase":"SECURITY"'

Invoke-Wf $scr @("gate", "--phase", "AUDIT", "--verdict", "CLEAR", "--actual", "96", "--target", "95") | Out-Null
Invoke-Wf $scr @("gate", "--phase", "SECURITY", "--verdict", "CLEAR") | Out-Null
$r = Invoke-Wf $scr @("next")
Assert-Contains "10 both parallel phases done -> advances to DOCUMENT" $r.Output '"phase":"DOCUMENT"'

Invoke-Wf $scr @("gate", "--phase", "DOCUMENT", "--verdict", "done") | Out-Null
$r = Invoke-Wf $scr @("next")
Assert-Contains "11 advances to VERIFY" $r.Output '"phase":"VERIFY"'

$r = Invoke-Wf $scr @("gate", "--phase", "VERIFY", "--verdict", "PASS")
Assert-Eq "12 VERIFY PASS triggers onPass=open-pr" "open-pr" (Get-JsonField $r.Output "onPass")
$r = Invoke-Wf $scr @("next")
Assert-Contains "13 pipeline reports complete after VERIFY" $r.Output '"status":"complete"'

"- [ ] t1 Do the thing" | Set-Content (Join-Path $scr ".llm/tasks.md")
$r = Invoke-Wf $scr @("complete", "--task", "t1")
Assert-Eq "14 complete marks task done" "true" (Get-JsonField $r.Output "taskMarked")
Assert-Contains "15 complete rewrites tasks.md checkbox" (Get-Content (Join-Path $scr ".llm/tasks.md") -Raw) "[x] t1"

$scrInfra = Join-Path $env:TEMP "wf-ps-infra-$(Get-Random)"
New-Scratch $scrInfra
Invoke-Wf $scrInfra @("init", "--task", "i1", "--pipeline", "infrastructure") | Out-Null
$r = Invoke-Wf $scrInfra @("gate", "--phase", "IMPLEMENT", "--verdict", "done", "--pipeline", "infrastructure")
Assert-Eq "16 infra pipeline: IMPLEMENT advances to SECURITY" "SECURITY" (Get-JsonField $r.Output "nextPhase")
Invoke-Wf $scrInfra @("gate", "--phase", "SECURITY", "--verdict", "CLEAR", "--pipeline", "infrastructure") | Out-Null
$r = Invoke-Wf $scrInfra @("gate", "--phase", "VERIFY", "--verdict", "PASS", "--pipeline", "infrastructure")
Assert-Eq "17 infra pipeline: VERIFY PASS -> open-pr, no further phase" "open-pr" (Get-JsonField $r.Output "onPass")

Write-Host ""
Write-Host "Tier 2 - adversarial / boundary"

$scr2 = Join-Path $env:TEMP "wf-ps-t2-$(Get-Random)"
New-Scratch $scr2
Invoke-Wf $scr2 @("init", "--task", "t1", "--pipeline", "software") | Out-Null
$r = Invoke-Wf $scr2 @("init", "--task", "t2", "--pipeline", "software")
Assert-Eq "18 init on a different task's branch asks (exit 2)" "2" $r.ExitCode
Assert-Contains "19 wrong-task-branch reason surfaced" $r.Output "wrong-task-branch"

Push-Location $scr2; git switch -c some-other-branch -q; Pop-Location
$r = Invoke-Wf $scr2 @("init", "--task", "t2", "--pipeline", "software")
Assert-Eq "20 init on an unrecognized branch asks (exit 2)" "2" $r.ExitCode
Assert-Contains "21 ambiguous-branch reason surfaced" $r.Output "ambiguous-branch"
Push-Location $scr2; git switch task/t1 -q; Pop-Location

Invoke-Wf $scr2 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Invoke-Wf $scr2 @("gate", "--phase", "RED", "--verdict", "done") | Out-Null
Invoke-Wf $scr2 @("gate", "--phase", "GREEN", "--verdict", "done") | Out-Null
Invoke-Wf $scr2 @("gate", "--phase", "REFACTOR", "--verdict", "CLEAN") | Out-Null

$r = Invoke-Wf $scr2 @("gate", "--phase", "AUDIT", "--verdict", "CLEAR", "--actual", "10", "--target", "95")
Assert-Eq "22 gate never ADVANCEs on an unmet threshold" "FAIL" (Get-JsonField $r.Output "result")
$r = Invoke-Wf $scr2 @("next")
Assert-Contains "23 AUDIT still pending after failed threshold (did not silently advance)" $r.Output '"phase":"AUDIT"'

$r = Invoke-Wf $scr2 @("gate", "--phase", "AUDIT", "--verdict", "CLEAR", "--actual", "96", "--target", "95")
Assert-Eq "24 gate advances once threshold is actually met" "ADVANCE" (Get-JsonField $r.Output "result")

$r = Invoke-Wf $scr2 @("gate", "--phase", "SECURITY", "--verdict", "BLOCKED", "--reason", "critical-finding")
Assert-Eq "25 gate PAUSEs on a recognized pauseWhen reason" "PAUSE" (Get-JsonField $r.Output "result")
Assert-Contains "26 Blocking Issues populated on PAUSE" (Get-Content (Join-Path $scr2 ".llm/workflow-state.md") -Raw) "critical-finding"

$r1 = Invoke-Wf $scr2 @("next")
$r2 = Invoke-Wf $scr2 @("next")
Assert-Eq "27 resumability: next is idempotent across repeated calls" $r1.Output $r2.Output
Assert-Contains "28 resumability: paused phase (SECURITY) still returned" $r1.Output '"phase":"SECURITY"'

Invoke-Wf $scr2 @("gate", "--phase", "SECURITY", "--verdict", "CLEAR") | Out-Null
Assert-Contains "29 clearing the pause resets Blocking Issues to [None]" (Get-Content (Join-Path $scr2 ".llm/workflow-state.md") -Raw) "[None]"
$r = Invoke-Wf $scr2 @("next")
Assert-Contains "30 pipeline resumes forward after the block clears" $r.Output '"phase":"DOCUMENT"'

$r = Invoke-Wf $scr2 @("gate", "--phase", "DOCUMENT", "--verdict", "done", "--reason", "not-a-real-reason")
Assert-Eq "31 an unrecognized --reason is rejected" "1" $r.ExitCode

$scr3 = Join-Path $env:TEMP "wf-ps-t3-$(Get-Random)"
New-Scratch $scr3
"## Verdict" | Set-Content (Join-Path $scr3 ".llm/spec-review/2026-01-01-test.md")
"CLEAR" | Add-Content (Join-Path $scr3 ".llm/spec-review/2026-01-01-test.md")
Invoke-Wf $scr3 @("init", "--task", "t3", "--pipeline", "software") | Out-Null
$r = Invoke-Wf $scr3 @("next")
Assert-Contains "32 SPEC_REVIEW_GATE auto-skips when a fresh CLEAR report exists" $r.Output '"phase":"RED"'

$scr4 = Join-Path $env:TEMP "wf-ps-t4-$(Get-Random)"
New-Scratch $scr4
"## Verdict" | Set-Content (Join-Path $scr4 ".llm/spec-review/2026-01-01-test.md")
"CLEAR" | Add-Content (Join-Path $scr4 ".llm/spec-review/2026-01-01-test.md")
Start-Sleep -Seconds 2
"newer spec" | Set-Content (Join-Path $scr4 "docs/spec/foo.md")
Push-Location $scr4; git add docs/spec/foo.md; git commit -q -m "update spec"; Pop-Location
Invoke-Wf $scr4 @("init", "--task", "t4", "--pipeline", "software") | Out-Null
$r = Invoke-Wf $scr4 @("next")
Assert-Contains "33 SPEC_REVIEW_GATE does not skip when the report predates a spec change" $r.Output '"phase":"SPEC_REVIEW_GATE"'

$scr5 = Join-Path $env:TEMP "wf-ps-t5-$(Get-Random)"
New-Scratch $scr5
Invoke-Wf $scr5 @("init", "--task", "sw", "--pipeline", "software") | Out-Null
Push-Location $scr5; git switch main -q; Pop-Location
Invoke-Wf $scr5 @("init", "--task", "in", "--pipeline", "infrastructure") | Out-Null
$r = Invoke-Wf $scr5 @("next")
Assert-Eq "34 next with two active pipelines and no --pipeline errors" "1" $r.ExitCode
$r = Invoke-Wf $scr5 @("next", "--pipeline", "software")
Assert-Contains "35 next --pipeline disambiguates correctly" $r.Output '"phase":"SPEC_REVIEW_GATE"'

$scr6 = Join-Path $env:TEMP "wf-ps-t6-$(Get-Random)"
New-Scratch $scr6
Invoke-Wf $scr6 @("init", "--task", "t1", "--pipeline", "software") | Out-Null
$r = Invoke-Wf $scr6 @("complete", "--task", "t1")
Assert-Eq "36 complete refuses when the pipeline isn't finished" "1" $r.ExitCode

Write-Host ""
Write-Host "Tier 3 - classify"

$scr7 = Join-Path $env:TEMP "wf-ps-t7-$(Get-Random)"
New-Scratch $scr7
@'
classify:
  frontend: ["docs/spec/components/**", "docs/spec/ui/**"]
  backend: ["docs/spec/interfaces/**"]
  infrastructure: ["docs/spec/infrastructure/**", "docs/spec/modules/**"]
'@ | Set-Content (Join-Path $scr7 ".tech-decisions.yml")
@'
- [ ] t1 Implement auth
  - Context: docs/spec/interfaces/auth-operations.md
- [ ] t2 Build login form
  - Context: docs/spec/components/login-form.md
- [ ] t3 Nothing resolvable
  - Context: no spec path here
- [ ] t4 Conflicting signals
  - Context: docs/spec/interfaces/x.md and docs/spec/components/y.md
'@ | Set-Content (Join-Path $scr7 ".llm/tasks.md")

$r = Invoke-Wf $scr7 @("classify", "--task", "t1")
Assert-Eq "37 classify resolves backend from docs/spec/interfaces/" "backend" (Get-JsonField $r.Output "domain")
$r = Invoke-Wf $scr7 @("classify", "--task", "t2")
Assert-Eq "38 classify resolves frontend from docs/spec/components/" "frontend" (Get-JsonField $r.Output "domain")
$r = Invoke-Wf $scr7 @("classify", "--task", "t3")
Assert-Eq "39 classify with no resolvable path is ambiguous" "ambiguous" (Get-JsonField $r.Output "domain")
$r = Invoke-Wf $scr7 @("classify", "--task", "t4")
Assert-Eq "40 classify with conflicting signals is ambiguous (preserved from the old prose)" "ambiguous" (Get-JsonField $r.Output "domain")
$r = Invoke-Wf $scr7 @("classify", "--path", "docs/spec/infrastructure/network-vpc.md")
Assert-Eq "41 classify resolves infrastructure via direct --path" "infrastructure" (Get-JsonField $r.Output "domain")
Remove-Item (Join-Path $scr7 ".tech-decisions.yml")
$r = Invoke-Wf $scr7 @("classify", "--task", "t1")
Assert-Eq "42 classify is ambiguous (not an error) when .tech-decisions.yml is absent" "ambiguous" (Get-JsonField $r.Output "domain")

Write-Host ""
Write-Host "Tier 4 - context"

$scr8 = Join-Path $env:TEMP "wf-ps-t8-$(Get-Random)"
New-Scratch $scr8
New-Item -ItemType Directory -Path (Join-Path $scr8 "docs/spec") -Force | Out-Null
@'
### ASSERT-0001: Login succeeds

```yaml
id: ASSERT-0001
module: auth
tags: [security]
given: a registered user with correct credentials
when: they submit the login form
then: a session token is issued
requirementRef: REQ-0001
```

### ASSERT-0002: Order total excludes tax

```yaml
id: ASSERT-0002
module: orders
given: a tax-exempt customer
when: an order total is calculated
then: tax is not applied
```
'@ | Set-Content (Join-Path $scr8 "docs/spec/assertions.md")

$r = Invoke-Wf $scr8 @("context", "--module", "auth")
Assert-Contains "43 context returns matching-module assertions" $r.Output "ASSERT-0001"
Assert-Contains "43b context surfaces an assertion's requirementRef when present" $r.Output "REQ-0001"
$r = Invoke-Wf $scr8 @("context", "--module", "orders")
Assert-Contains "44 context scopes strictly to the requested module" $r.Output "ASSERT-0002"
if ($r.Output.Contains("ASSERT-0001")) { Fail "44b context must not leak other modules' assertions" "found ASSERT-0001 in orders query" } else { Pass "44b context must not leak other modules' assertions" }
$r = Invoke-Wf $scr8 @("context", "--module", "orders", "--agent", "security-reviewer")
Assert-Eq "45 context filters to security-tagged only for security-reviewer" '{"module":"orders","assertions":[]}' $r.Output
$r = Invoke-Wf $scr8 @("context", "--module", "auth", "--agent", "security-reviewer")
Assert-Contains "46 security-reviewer still sees security-tagged assertions for its module" $r.Output "ASSERT-0001"
$r = Invoke-Wf $scr8 @("context", "--module", "nothing")
Assert-Eq "47 context returns an empty list for an unmatched module, not an error" '{"module":"nothing","assertions":[]}' $r.Output
Remove-Item (Join-Path $scr8 "docs/spec/assertions.md")
$r = Invoke-Wf $scr8 @("context", "--module", "auth")
Assert-Eq "48 context is empty (not an error) when assertions.md doesn't exist" '{"module":"auth","assertions":[]}' $r.Output

Write-Host ""
Write-Host "Tier 5 - tasks next"

$scr9 = Join-Path $env:TEMP "wf-ps-t9-$(Get-Random)"
New-Scratch $scr9
@'
- [ ] 1.0 Core shared types

```yaml
id: "1.0"
title: "Core shared types"
deps: []
criticality: domain_logic
specRefs: []
status: ready
domain: backend
```

- [ ] 1.1 Domain types

```yaml
id: "1.1"
title: "Domain types"
deps: ["1.0"]
criticality: domain_logic
specRefs: []
status: ready
domain: backend
```
'@ | Set-Content (Join-Path $scr9 ".llm/tasks.md")

$r = Invoke-Wf $scr9 @("tasks", "next")
Assert-Contains "49 tasks next returns the task with no unmet deps first" $r.Output '"id":"1.0"'

function Set-FirstReadyDone([string]$Dir) {
    $path = Join-Path $Dir ".llm/tasks.md"
    $raw = Get-Content $path -Raw
    $idx = $raw.IndexOf("status: ready")
    $raw = $raw.Remove($idx, "status: ready".Length).Insert($idx, "status: done")
    Set-Content -Path $path -Value $raw -NoNewline
}

Set-FirstReadyDone $scr9
$r = Invoke-Wf $scr9 @("tasks", "next")
Assert-Contains "50 tasks next advances once the dependency is done" $r.Output '"id":"1.1"'

Set-FirstReadyDone $scr9
$r = Invoke-Wf $scr9 @("tasks", "next")
Assert-Eq "51 tasks next reports none-ready once every task is done" '{"task":null,"reason":"none-ready"}' $r.Output

@'
- [ ] 2.0 A

```yaml
id: "2.0"
title: "A"
deps: ["2.1"]
criticality: domain_logic
specRefs: []
status: ready
domain: backend
```

- [ ] 2.1 B

```yaml
id: "2.1"
title: "B"
deps: ["2.0"]
criticality: domain_logic
specRefs: []
status: ready
domain: backend
```
'@ | Set-Content (Join-Path $scr9 ".llm/tasks.md")
$r = Invoke-Wf $scr9 @("tasks", "next")
Assert-Eq "52 tasks next detects a dependency cycle instead of silently misordering" "cycle-detected" (Get-JsonField $r.Output "reason")

Remove-Item (Join-Path $scr9 ".llm/tasks.md")
$r = Invoke-Wf $scr9 @("tasks", "next")
Assert-Eq "53 tasks next is a clean no-op (not an error) when tasks.md is absent" '{"task":null,"reason":"no-tasks-file"}' $r.Output

$scr10 = Join-Path $env:TEMP "wf-ps-t10-$(Get-Random)"
New-Scratch $scr10
@'
- [ ] c1 Some task

```yaml
id: "c1"
title: "Some task"
deps: []
criticality: domain_logic
specRefs: []
status: ready
domain: backend
```
'@ | Set-Content (Join-Path $scr10 ".llm/tasks.md")
Invoke-Wf $scr10 @("init", "--task", "c1", "--pipeline", "software") | Out-Null
Invoke-Wf $scr10 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Invoke-Wf $scr10 @("gate", "--phase", "RED", "--verdict", "done") | Out-Null
Invoke-Wf $scr10 @("gate", "--phase", "GREEN", "--verdict", "done") | Out-Null
Invoke-Wf $scr10 @("gate", "--phase", "REFACTOR", "--verdict", "CLEAN") | Out-Null
Invoke-Wf $scr10 @("gate", "--phase", "AUDIT", "--verdict", "CLEAR") | Out-Null
Invoke-Wf $scr10 @("gate", "--phase", "SECURITY", "--verdict", "CLEAR") | Out-Null
Invoke-Wf $scr10 @("gate", "--phase", "DOCUMENT", "--verdict", "done") | Out-Null
Invoke-Wf $scr10 @("gate", "--phase", "VERIFY", "--verdict", "PASS") | Out-Null
Invoke-Wf $scr10 @("complete", "--task", "c1") | Out-Null
$content = Get-Content (Join-Path $scr10 ".llm/tasks.md") -Raw
Assert-Contains "54 complete also flips the structured task record's status to done" $content "status: done"
Assert-Contains "55 complete still flips the prose checkbox too" $content "- [x] c1"

Write-Host ""
Write-Host "Tier 6 - risk-tier gate"

$scr11 = Join-Path $env:TEMP "wf-ps-t11-$(Get-Random)"
New-Scratch $scr11
Invoke-Wf $scr11 @("init", "--task", "r1", "--pipeline", "software") | Out-Null

$r = Invoke-Wf $scr11 @("tier", "--files-changed", "2")
Assert-Eq "56 tier computes minimal for <=3 files changed, no risk paths" "minimal" (Get-JsonField $r.Output "tier")
$stateContent = Get-Content (Join-Path $scr11 ".llm/workflow-state.md") -Raw
Assert-Contains "57 tier writes Tier + Tier Reason into the active state file" $stateContent "**Tier:** minimal"

$r = Invoke-Wf $scr11 @("tier", "--files-changed", "8")
Assert-Eq "58 tier computes standard for a mid-range file count" "standard" (Get-JsonField $r.Output "tier")

$r = Invoke-Wf $scr11 @("tier", "--files-changed", "20")
Assert-Eq "59 tier computes elevated for >15 files changed" "elevated" (Get-JsonField $r.Output "tier")

$r = Invoke-Wf $scr11 @("tier", "--files-changed", "2", "--untested-module", "auth")
Assert-Eq "60 tier computes elevated when a touched module has no existing tests" "elevated" (Get-JsonField $r.Output "tier")

'risk_paths: ["src/auth/**", "src/safety/**"]' | Set-Content (Join-Path $scr11 ".tech-decisions.yml")
$r = Invoke-Wf $scr11 @("tier", "--files-changed", "2", "--path", "src/auth/session.rs")
Assert-Eq "61 tier computes elevated when a touched path matches risk_paths, regardless of file count" "elevated" (Get-JsonField $r.Output "tier")

$r = Invoke-Wf $scr11 @("tier", "--files-changed", "2", "--override", "elevated")
Assert-Eq "62 human override up (minimal -> elevated) is accepted" "elevated" (Get-JsonField $r.Output "tier")
Assert-Eq "63 an accepted override reports overridden=true" "true" (Get-JsonField $r.Output "overridden")

$r = Invoke-Wf $scr11 @("tier", "--files-changed", "2", "--path", "src/auth/session.rs", "--override", "minimal")
Assert-Eq "64 override cannot force a risk_paths-triggered elevated tier down" "elevated" (Get-JsonField $r.Output "tier")
Assert-Contains "65 a rejected override explains the refusal" $r.Output "cannot override down from elevated"
Remove-Item (Join-Path $scr11 ".tech-decisions.yml")

$scr12 = Join-Path $env:TEMP "wf-ps-t12-$(Get-Random)"
New-Scratch $scr12
Invoke-Wf $scr12 @("init", "--task", "r2", "--pipeline", "software") | Out-Null
Invoke-Wf $scr12 @("tier", "--files-changed", "2") | Out-Null
Invoke-Wf $scr12 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Invoke-Wf $scr12 @("gate", "--phase", "RED", "--verdict", "done") | Out-Null
Invoke-Wf $scr12 @("gate", "--phase", "GREEN", "--verdict", "done") | Out-Null
$r = Invoke-Wf $scr12 @("gate", "--phase", "REFACTOR", "--verdict", "CLEAN")
Assert-Eq "66 gate on REFACTOR advances to AUDIT even under tier:minimal (the skip is lazy, applied only by next)" "AUDIT" (Get-JsonField $r.Output "nextPhase")
$r = Invoke-Wf $scr12 @("next")
Assert-Contains "67 next under tier:minimal returns only SECURITY (AUDIT auto-skipped)" $r.Output '"phase":"SECURITY"'
if ($r.Output.Contains('"phase":"AUDIT"')) {
    Fail "68 AUDIT must not appear in next's phases under tier:minimal" "found AUDIT in $($r.Output)"
} else {
    Pass "68 AUDIT must not appear in next's phases under tier:minimal"
}
$r = Invoke-Wf $scr12 @("gate", "--phase", "SECURITY", "--verdict", "CLEAR")
Assert-Eq "69 gate on SECURITY advances to DOCUMENT even under tier:minimal (the skip is lazy)" "DOCUMENT" (Get-JsonField $r.Output "nextPhase")
$r = Invoke-Wf $scr12 @("next")
Assert-Contains "70 next under tier:minimal returns VERIFY directly (DOCUMENT auto-skipped)" $r.Output '"phase":"VERIFY"'
$stateContent12 = Get-Content (Join-Path $scr12 ".llm/workflow-state.md") -Raw
Assert-Contains "70b a skipOnTier skip leaves an audit-trail entry Verifier can recognize as exempt" $stateContent12 "AUDIT: skipped (tier: minimal, skipOnTier)"

Write-Host ""
Write-Host "Tier 7 - code-review fixes (multi-reason pauseWhen, init resume, skip audit trail)"

$scr13 = Join-Path $env:TEMP "wf-ps-t13-$(Get-Random)"
New-Scratch $scr13
Invoke-Wf $scr13 @("init", "--task", "p1", "--pipeline", "software") | Out-Null
Invoke-Wf $scr13 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Invoke-Wf $scr13 @("gate", "--phase", "RED", "--verdict", "done") | Out-Null
Invoke-Wf $scr13 @("gate", "--phase", "GREEN", "--verdict", "done") | Out-Null
Invoke-Wf $scr13 @("gate", "--phase", "REFACTOR", "--verdict", "CLEAN") | Out-Null
$r = Invoke-Wf $scr13 @("gate", "--phase", "AUDIT", "--verdict", "BLOCKED", "--reason", "safety-critical-survivor")
Assert-Eq "71 AUDIT pauses on the FIRST of its two pauseWhen reasons (safety-critical-survivor)" "PAUSE" (Get-JsonField $r.Output "result")

$scr14 = Join-Path $env:TEMP "wf-ps-t14-$(Get-Random)"
New-Scratch $scr14
Invoke-Wf $scr14 @("init", "--task", "p2", "--pipeline", "software") | Out-Null
Invoke-Wf $scr14 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Invoke-Wf $scr14 @("gate", "--phase", "RED", "--verdict", "done") | Out-Null
Invoke-Wf $scr14 @("gate", "--phase", "GREEN", "--verdict", "done") | Out-Null
Invoke-Wf $scr14 @("gate", "--phase", "REFACTOR", "--verdict", "CLEAN") | Out-Null
$r = Invoke-Wf $scr14 @("gate", "--phase", "AUDIT", "--verdict", "BLOCKED", "--reason", "formal-counterexample")
Assert-Eq "72 AUDIT pauses on the SECOND of its two pauseWhen reasons (formal-counterexample)" "PAUSE" (Get-JsonField $r.Output "result")

$scr15 = Join-Path $env:TEMP "wf-ps-t15-$(Get-Random)"
New-Scratch $scr15
Invoke-Wf $scr15 @("init", "--task", "p3", "--pipeline", "software") | Out-Null
Invoke-Wf $scr15 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Invoke-Wf $scr15 @("gate", "--phase", "RED", "--verdict", "done") | Out-Null
$r = Invoke-Wf $scr15 @("init", "--task", "p3", "--pipeline", "software")
Assert-Eq "73 re-running init on an in-progress task resumes (returns the current phase, not the first)" "GREEN" (Get-JsonField $r.Output "phase")
$stateContent15 = Get-Content (Join-Path $scr15 ".llm/workflow-state.md") -Raw
Assert-Contains "74 re-running init does not reset Current Phase in the state file" $stateContent15 "**Current Phase:** GREEN"

Write-Host ""
Write-Host "Tier 8 - isolation"

$scr16 = Join-Path $env:TEMP "wf-ps-t16-$(Get-Random)"
New-Scratch $scr16
Invoke-Wf $scr16 @("init", "--task", "iso1", "--pipeline", "software") | Out-Null
$r = Invoke-Wf $scr16 @("next")
Assert-Contains "75 next reports isolation:direct for SPEC_REVIEW_GATE (no isolation key -> default)" $r.Output '"phase":"SPEC_REVIEW_GATE","agent":"Spec Reviewer","isolation":"direct"'
$stateContent16 = Get-Content (Join-Path $scr16 ".llm/workflow-state.md") -Raw
Assert-Contains "76 next's isolation resolution is cached in the state file" $stateContent16 "SPEC_REVIEW_GATE: direct (repo default)"

Invoke-Wf $scr16 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
$r = Invoke-Wf $scr16 @("next")
Assert-Contains "77 next reports isolation:container for RED (pipelines.yml default)" $r.Output '"phase":"RED","agent":"Tester","isolation":"container"'

$scr17 = Join-Path $env:TEMP "wf-ps-t17-$(Get-Random)"
New-Scratch $scr17
@'
isolation:
  overrides:
    RED: direct
'@ | Set-Content (Join-Path $scr17 ".tech-decisions.yml")
Invoke-Wf $scr17 @("init", "--task", "iso2", "--pipeline", "software") | Out-Null
Invoke-Wf $scr17 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
$r = Invoke-Wf $scr17 @("next")
Assert-Contains "78 a repo-level .tech-decisions.yml override flips a phase's default" $r.Output '"phase":"RED","agent":"Tester","isolation":"direct"'
$stateContent17 = Get-Content (Join-Path $scr17 ".llm/workflow-state.md") -Raw
Assert-Contains "78b the override's source is recorded, not just its mode" $stateContent17 "RED: direct (repo override)"

# Caching: once next has resolved+recorded a phase's mode, a LATER
# .tech-decisions.yml edit must not retroactively change it.
$scr18 = Join-Path $env:TEMP "wf-ps-t18-$(Get-Random)"
New-Scratch $scr18
Invoke-Wf $scr18 @("init", "--task", "iso3", "--pipeline", "software") | Out-Null
Invoke-Wf $scr18 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Invoke-Wf $scr18 @("next") | Out-Null
@'
isolation:
  overrides:
    RED: direct
'@ | Set-Content (Join-Path $scr18 ".tech-decisions.yml")
$r = Invoke-Wf $scr18 @("next")
Assert-Contains "79 a cached isolation mode survives a later .tech-decisions.yml edit (not re-resolved)" $r.Output '"phase":"RED","agent":"Tester","isolation":"container"'

# workflow isolation --override: strengthening is allowed.
$scr19 = Join-Path $env:TEMP "wf-ps-t19-$(Get-Random)"
New-Scratch $scr19
Invoke-Wf $scr19 @("init", "--task", "iso4", "--pipeline", "software") | Out-Null
$r = Invoke-Wf $scr19 @("isolation", "--phase", "SECURITY", "--override", "container")
Assert-Eq "80 isolation --override strengthens a direct-by-default phase" "container" (Get-JsonField $r.Output "isolation")
Assert-Eq "81 a successful strengthening override reports overridden=true" "true" (Get-JsonField $r.Output "overridden")
$stateContent19 = Get-Content (Join-Path $scr19 ".llm/workflow-state.md") -Raw
Assert-Contains "82 a strengthening override is recorded in the state file" $stateContent19 "SECURITY: container (task override"

# workflow isolation --override: weakening is refused outright.
$r = Invoke-Wf $scr19 @("isolation", "--phase", "RED", "--override", "direct")
Assert-Eq "83 isolation --override refuses to weaken a container-by-default phase" "container" (Get-JsonField $r.Output "isolation")
Assert-Eq "84 a refused override reports overridden=false" "false" (Get-JsonField $r.Output "overridden")
Assert-Contains "85 a refused override explains the refusal" $r.Output "cannot downgrade RED below repo policy"
$stateContent19b = Get-Content (Join-Path $scr19 ".llm/workflow-state.md") -Raw
if ($stateContent19b.Contains("RED: ")) {
    Fail "86 a refused override must not be written to the state file" "found a RED: line after refusal"
} else {
    Pass "86 a refused override must not be written to the state file"
}

# workflow isolation --override: requesting the mode already in effect is a no-op.
$r = Invoke-Wf $scr19 @("isolation", "--phase", "RED", "--override", "container")
Assert-Eq "87 requesting the already-effective mode is a no-op (not an error)" "false" (Get-JsonField $r.Output "overridden")
Assert-Eq "88 a no-op override still reports the correct isolation" "container" (Get-JsonField $r.Output "isolation")

$r = Invoke-Wf $scr19 @("isolation", "--phase", "RED", "--override", "bogus")
Assert-Eq "89 an invalid --override value is rejected" "1" $r.ExitCode

$scr20 = Join-Path $env:TEMP "wf-ps-t20-$(Get-Random)"
New-Scratch $scr20
Invoke-Wf $scr20 @("init", "--task", "iso5", "--pipeline", "infrastructure") | Out-Null
$r = Invoke-Wf $scr20 @("next", "--pipeline", "infrastructure")
Assert-Contains "90 infra pipeline: IMPLEMENT defaults to isolation:container" $r.Output '"phase":"IMPLEMENT","agent":"Infrastructure Engineer","isolation":"container"'
Invoke-Wf $scr20 @("gate", "--phase", "IMPLEMENT", "--verdict", "done", "--pipeline", "infrastructure") | Out-Null
$r = Invoke-Wf $scr20 @("next", "--pipeline", "infrastructure")
Assert-Contains "91 infra pipeline: SECURITY defaults to isolation:direct" $r.Output '"phase":"SECURITY","agent":"Security Reviewer","isolation":"direct"'

Write-Host ""
Write-Host "Tier 9 - run-isolated (materialization)"

# Write-IsolationInput/Resolve-IsolationImage are exercised directly from
# here on (dot-sourcing workflow.ps1 with the "__noop__" sentinel, same as
# test-container-spawn.ps1), not through the full `run-isolated` CLI --
# that command now always attempts a real container spawn once
# materialization succeeds (sections 3/3.4), which needs docker/podman and
# a git-wrapper.sh this suite's scratch repos don't carry (New-Scratch only
# copies workflow.ps1/pipelines.yml/lib). The real spawn-and-poll path is
# covered end to end, against a stub entrypoint (no ANTHROPIC_API_KEY is
# available in this dev environment, and a real `claude -p` call would
# spend real money), in
# tools/workflow/isolation/test/test-container-spawn.ps1. This keeps the
# main suite dependency-free while still testing the real production
# materialization/image-resolution functions, not a reimplementation.
. $WorkflowPs1 -Command "__noop__"

function Set-TestSectionMarker([string]$Path, [string]$Heading, [string]$Marker) {
    $lines = Get-Content $Path
    $result = New-Object System.Collections.Generic.List[string]
    $replaceNext = $false
    foreach ($line in $lines) {
        if ($replaceNext) { $result.Add($Marker); $replaceNext = $false; continue }
        $result.Add($line)
        if ($line -eq "## $Heading") { $replaceNext = $true }
    }
    Set-Content -Path $Path -Value $result
}

$scr21 = Join-Path $env:TEMP "wf-ps-t21-$(Get-Random)"
New-Scratch $scr21
Invoke-Wf $scr21 @("init", "--task", "iso-run1", "--pipeline", "software") | Out-Null
Invoke-Wf $scr21 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null

$stateFile21 = Join-Path $scr21 ".llm/workflow-state.md"
Set-TestSectionMarker $stateFile21 "Standards" "TEST STANDARDS MARKER"
Set-TestSectionMarker $stateFile21 "Context" "TEST CONTEXT MARKER"

$inputDir21 = Write-IsolationInput -Root $scr21 -Task "iso-run1" -Pipeline "software" -Branch "task/iso-run1" -PhaseId "RED" -Agent "Tester" -StateFile $stateFile21 -Slug "iso-run1"
Assert-Eq "92 Write-IsolationInput returns the input directory" (Join-Path $scr21 ".llm/isolation/iso-run1/RED/input") $inputDir21

$promptPath = Join-Path $scr21 ".llm/isolation/iso-run1/RED/input/prompt.md"
$taskJsonPath = Join-Path $scr21 ".llm/isolation/iso-run1/RED/input/task.json"
if (Test-Path $promptPath) { Pass "93 prompt.md was materialized" } else { Fail "93 prompt.md was materialized" "not found at $promptPath" }
$promptContent = if (Test-Path $promptPath) { Get-Content $promptPath -Raw } else { "" }
Assert-Contains "94 prompt.md carries the live Standards section content" $promptContent "TEST STANDARDS MARKER"
Assert-Contains "95 prompt.md carries the live Context section content" $promptContent "TEST CONTEXT MARKER"
if ($promptContent.Contains("## Diff")) {
    Fail "96 RED must not get a Diff section (nothing to diff before GREEN runs)" "found ## Diff"
} else {
    Pass "96 RED must not get a Diff section (nothing to diff before GREEN runs)"
}
$taskJsonContent = if (Test-Path $taskJsonPath) { Get-Content $taskJsonPath -Raw } else { "" }
Assert-Contains "97 task.json carries the resolved phase" $taskJsonContent '"phase":"RED"'
Assert-Contains "98 task.json carries the resolved agent name" $taskJsonContent '"agent":"Tester"'
Assert-Contains "99 task.json carries the resolved pipeline" $taskJsonContent '"pipeline":"software"'

Invoke-Wf $scr21 @("gate", "--phase", "RED", "--verdict", "done") | Out-Null
Invoke-Wf $scr21 @("gate", "--phase", "GREEN", "--verdict", "done") | Out-Null
"a change" | Add-Content (Join-Path $scr21 "README.md")
Push-Location $scr21; git add README.md; git commit -q -m "a change for the diff"; Pop-Location
Write-IsolationInput -Root $scr21 -Task "iso-run1" -Pipeline "software" -Branch "task/iso-run1" -PhaseId "REFACTOR" -Agent "Refactor" -StateFile $stateFile21 -Slug "iso-run1" | Out-Null
$refactorPromptPath = Join-Path $scr21 ".llm/isolation/iso-run1/REFACTOR/input/prompt.md"
$refactorPromptContent = if (Test-Path $refactorPromptPath) { Get-Content $refactorPromptPath -Raw } else { "" }
Assert-Contains "100 REFACTOR gets a Diff section" $refactorPromptContent "## Diff"
Assert-Contains "101 the Diff section shows the actual change" $refactorPromptContent "a change"

$r = Invoke-Wf $scr21 @("run-isolated", "--phase", "SECURITY")
Assert-Eq "102 run-isolated on a direct phase refuses outright, before ever materializing or touching a runtime" "1" $r.ExitCode
Assert-Contains "103 the refusal names the resolved (direct) mode" $r.Output "is not isolated"

Write-Host ""
Write-Host "Tier 10 - image resolution"

$scr22 = Join-Path $env:TEMP "wf-ps-t22-$(Get-Random)"
New-Scratch $scr22
Invoke-Wf $scr22 @("init", "--task", "img1", "--pipeline", "software") | Out-Null
Invoke-Wf $scr22 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Write-IsolationInput -Root $scr22 -Task "img1" -Pipeline "software" -Branch "task/img1" -PhaseId "RED" -Agent "Tester" -StateFile (Join-Path $scr22 ".llm/workflow-state.md") -Slug "img1" | Out-Null
$out = Get-Content (Join-Path $scr22 ".llm/isolation/img1/RED/input/task.json") -Raw
Assert-Contains "104 no .tech-decisions.yml, no devcontainer.json -> generic fallback image" $out '"image":"image:debian:12-slim"'

$scr23 = Join-Path $env:TEMP "wf-ps-t23-$(Get-Random)"
New-Scratch $scr23
@'
toolchains:
  default: null

  detect:
    - if_exists: "Cargo.toml"
      toolchain: rust
    - if_exists: "package.json"
      toolchain: typescript
'@ | Set-Content (Join-Path $scr23 ".tech-decisions.yml")
"" | Set-Content (Join-Path $scr23 "Cargo.toml")
Push-Location $scr23; git add Cargo.toml .tech-decisions.yml; git commit -q -m "add cargo"; Pop-Location
Invoke-Wf $scr23 @("init", "--task", "img2", "--pipeline", "software") | Out-Null
Invoke-Wf $scr23 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Write-IsolationInput -Root $scr23 -Task "img2" -Pipeline "software" -Branch "task/img2" -PhaseId "RED" -Agent "Tester" -StateFile (Join-Path $scr23 ".llm/workflow-state.md") -Slug "img2" | Out-Null
$out = Get-Content (Join-Path $scr23 ".llm/isolation/img2/RED/input/task.json") -Raw
Assert-Contains "105 toolchains.detect matches Cargo.toml -> rust image" $out '"image":"image:rust:1-slim"'

$scr24 = Join-Path $env:TEMP "wf-ps-t24-$(Get-Random)"
New-Scratch $scr24
"" | Set-Content (Join-Path $scr24 "Cargo.toml")
New-Item -ItemType Directory -Path (Join-Path $scr24 ".devcontainer") -Force | Out-Null
@'
{
  "name": "test",
  "image": "custom/foo:latest"
}
'@ | Set-Content (Join-Path $scr24 ".devcontainer/devcontainer.json")
Push-Location $scr24; git add Cargo.toml .devcontainer/devcontainer.json; git commit -q -m "add devcontainer"; Pop-Location
Invoke-Wf $scr24 @("init", "--task", "img3", "--pipeline", "software") | Out-Null
Invoke-Wf $scr24 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Write-IsolationInput -Root $scr24 -Task "img3" -Pipeline "software" -Branch "task/img3" -PhaseId "RED" -Agent "Tester" -StateFile (Join-Path $scr24 ".llm/workflow-state.md") -Slug "img3" | Out-Null
$out = Get-Content (Join-Path $scr24 ".llm/isolation/img3/RED/input/task.json") -Raw
Assert-Contains "106 a devcontainer.json image field takes precedence over toolchain detection" $out '"image":"image:custom/foo:latest"'

$scr25 = Join-Path $env:TEMP "wf-ps-t25-$(Get-Random)"
New-Scratch $scr25
New-Item -ItemType Directory -Path (Join-Path $scr25 ".devcontainer") -Force | Out-Null
@'
{
  "name": "test",
  "build": { "dockerfile": "Dockerfile", "context": ".." }
}
'@ | Set-Content (Join-Path $scr25 ".devcontainer/devcontainer.json")
Push-Location $scr25; git add .devcontainer/devcontainer.json; git commit -q -m "add devcontainer build"; Pop-Location
Invoke-Wf $scr25 @("init", "--task", "img4", "--pipeline", "software") | Out-Null
Invoke-Wf $scr25 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Write-IsolationInput -Root $scr25 -Task "img4" -Pipeline "software" -Branch "task/img4" -PhaseId "RED" -Agent "Tester" -StateFile (Join-Path $scr25 ".llm/workflow-state.md") -Slug "img4" | Out-Null
$out = Get-Content (Join-Path $scr25 ".llm/isolation/img4/RED/input/task.json") -Raw
Assert-Contains "107 a devcontainer.json build block resolves to a build: spec, not an image pull" $out '"image":"build:Dockerfile:.."'

$scr26 = Join-Path $env:TEMP "wf-ps-t26-$(Get-Random)"
New-Scratch $scr26
@'
toolchains:
  default: rust

  detect:
    - if_exists: "pyproject.toml"
      toolchain: python
'@ | Set-Content (Join-Path $scr26 ".tech-decisions.yml")
Push-Location $scr26; git add .tech-decisions.yml; git commit -q -m "add tech-decisions"; Pop-Location
Invoke-Wf $scr26 @("init", "--task", "img5", "--pipeline", "software") | Out-Null
Invoke-Wf $scr26 @("gate", "--phase", "SPEC_REVIEW_GATE", "--verdict", "CLEAR") | Out-Null
Write-IsolationInput -Root $scr26 -Task "img5" -Pipeline "software" -Branch "task/img5" -PhaseId "RED" -Agent "Tester" -StateFile (Join-Path $scr26 ".llm/workflow-state.md") -Slug "img5" | Out-Null
$out = Get-Content (Join-Path $scr26 ".llm/isolation/img5/RED/input/task.json") -Raw
Assert-Contains "108 no if_exists match falls back to toolchains.default" $out '"image":"image:rust:1-slim"'

Write-Host ""
Write-Host "Tier 11 - real entrypoint command construction (section 3.4)"

# Build-IsolationEntrypointCommand needs no container runtime at all -- it
# only builds a command string -- so the verified flags it must carry are
# checked here, dependency-free. The real spawn+liveness wiring that RUNS
# this command is covered in test-container-spawn.ps1 instead, against a
# stub, for the reasons noted in Tier 9 above.
$entry = Build-IsolationEntrypointCommand -InputDir "/isolation/input" -OutputDir "/isolation/output" -LogPath "/isolation/run.jsonl" -AgentDefsFile "/isolation/input/agents.json" -AgentSlug "tester"
Assert-Contains "109 the entrypoint reads the materialized prompt.md" $entry "cat '/isolation/input/prompt.md'"
Assert-Contains "110 --bare is set (section 3.4: never auto-discover the target repo's own CLAUDE.md/hooks/MCP)" $entry "--bare"
Assert-Contains "111 --restricted is set (never load the target repo's own .claude/settings.json)" $entry "--restricted"
Assert-Contains "112 --permission-mode dontAsk is set" $entry "--permission-mode dontAsk"
Assert-Contains "113 --permission-prompts none is set (removes AskUserQuestion from the tool list entirely)" $entry "--permission-prompts none"
Assert-Contains "114 Bash/Read/Edit are restored via --tools after --restricted strips them" $entry '--tools "Bash,Read,Edit"'
Assert-Contains "115 --output-format stream-json is set (what gets piped to run.jsonl)" $entry "--output-format stream-json"
Assert-Contains "116 --include-partial-messages is set" $entry "--include-partial-messages"
Assert-Contains "117 --max-budget-usd is set (section 6's hardcoded v1 default)" $entry "--max-budget-usd"
Assert-Contains "118 the event stream is redirected to the host-visible run.jsonl path" $entry "/isolation/run.jsonl"
Assert-Contains "119 Claude Code's own install is bootstrapped (the image doesn't ship it)" $entry "claude.ai/install.sh"
Assert-Contains "119b --agents registers the agent definition file" $entry "--agents '/isolation/input/agents.json'"
Assert-Contains "119c --agent selects it for the top-level session (not just delegation)" $entry "--agent 'tester'"

$env:WORKFLOW_ISOLATION_TEST_ENTRYPOINT = "echo stub"
$entry2 = Build-IsolationEntrypointCommand -InputDir "/isolation/input" -OutputDir "/isolation/output" -LogPath "/isolation/run.jsonl" -AgentDefsFile "/isolation/input/agents.json" -AgentSlug "tester"
Remove-Item Env:\WORKFLOW_ISOLATION_TEST_ENTRYPOINT
Assert-Eq "120 WORKFLOW_ISOLATION_TEST_ENTRYPOINT substitutes the real command verbatim (test-only seam)" "echo stub" $entry2

Write-Host ""
Write-Host "Tier 12 - agent persona injection (--agents/--agent, found while staging a real test)"

# Runs an expression in a fresh child pwsh process, after dot-sourcing
# workflow.ps1 with the "__noop__" sentinel -- a child process, not direct
# dot-sourcing in this test's own process, because Fail calls exit, which
# would kill this test runner itself if an error-path call ran in-process.
# Mirrors test-container-spawn.ps1's own Invoke-IsolationFn helper.
function Invoke-IsolationFn([string]$Expr) {
    $cmd = ". '$WorkflowPs1' -Command '__noop__'; $Expr"
    $out = & pwsh -NoProfile -Command $cmd 2>&1
    return [PSCustomObject]@{ Output = ($out -join "`n"); ExitCode = $LASTEXITCODE }
}

Assert-Eq "121 agent-name mapping: Tester" "tester.md" (Get-IsolationAgentDefinitionFile -AgentName "Tester")
Assert-Eq "122 agent-name mapping: Coder" "coder.md" (Get-IsolationAgentDefinitionFile -AgentName "Coder")
Assert-Eq "123 agent-name mapping: Refactor" "refactor.md" (Get-IsolationAgentDefinitionFile -AgentName "Refactor")
Assert-Eq "124 agent-name mapping: QA Engineer" "qa-engineer.md" (Get-IsolationAgentDefinitionFile -AgentName "QA Engineer")
Assert-Eq "125 agent-name mapping: Infrastructure Engineer does NOT follow the mechanical lowercase/hyphenate pattern" "infra-engineer.md" (Get-IsolationAgentDefinitionFile -AgentName "Infrastructure Engineer")

$r = Invoke-IsolationFn "Get-IsolationAgentDefinitionFile -AgentName 'Nonexistent Agent'"
Assert-Eq "126 an unmapped agent name is refused, not silently guessed" "1" $r.ExitCode

# A self-contained fixture "claude home" (not this dev machine's real
# ~/.claude/agents/) -- Build-IsolationAgentDefinition's -ClaudeHome
# parameter exists specifically so this suite can stay dependency-free
# and deterministic rather than relying on whatever happens to be
# globally installed on the machine running it.
$fixtureHome = Join-Path $env:TEMP "wf-agent-fixture-$(Get-Random)"
New-Item -ItemType Directory -Path "$fixtureHome/agents" -Force | Out-Null
@'
---
name: "Tester"
description: A test fixture description with "quotes" and a \backslash.
tools:
  - Read
tier: balanced
---

## Role

Line one of the body.
Line two, with a "quoted" word and a \backslash too.
'@ | Set-Content (Join-Path $fixtureHome "agents/tester.md")

$outJson = Join-Path $env:TEMP "wf-agent-def-$(Get-Random).json"
$slug = Build-IsolationAgentDefinition -AgentName "Tester" -OutFile $outJson -ClaudeHome $fixtureHome
Assert-Eq "127 the returned slug is the filename stem" "tester" $slug
$jsonContent = Get-Content $outJson -Raw
Assert-Contains "128 the written file is valid-shaped JSON (opens with the slug key)" $jsonContent '{"tester":{"description":"'
Assert-Contains "129 the description field is extracted from frontmatter" $jsonContent 'A test fixture description'
Assert-Contains "130 embedded quotes in the description are escaped" $jsonContent '\"quotes\"'
Assert-Contains "131 embedded backslashes are escaped" $jsonContent '\\backslash'
Assert-Contains "132 the prompt field carries the body, not the frontmatter" $jsonContent 'Line one of the body.'
if ($jsonContent.Contains("tools:")) {
    Fail "133 frontmatter fields (tools/tier) are not forwarded into the prompt" "found 'tools:' in output"
} else {
    Pass "133 frontmatter fields (tools/tier) are not forwarded into the prompt"
}
Assert-Contains "134 multi-line body content is joined with an escaped newline, not a raw line break" $jsonContent 'Line one of the body.\nLine two'

$emptyHome = Join-Path $env:TEMP "wf-agent-empty-$(Get-Random)"
New-Item -ItemType Directory -Path $emptyHome -Force | Out-Null
$r = Invoke-IsolationFn "Build-IsolationAgentDefinition -AgentName 'Tester' -OutFile (Join-Path '$env:TEMP' 'wf-agent-out-$(Get-Random).json') -ClaudeHome '$emptyHome'"
Assert-Eq "135 a missing agent definition file refuses loudly rather than silently omitting the persona" "1" $r.ExitCode
Assert-Contains "136 the refusal names what's missing and how to fix it" $r.Output "run tools/ai-bootstrap/install.ps1 first"

Write-Host ""
Write-Host "=== Results: $($script:PassCount) passed, $($script:FailCount) failed ==="
if ($script:FailCount -gt 0) {
    Write-Host "Failed scenarios:"
    foreach ($n in $script:FailedNames) { Write-Host "  - $n" }
    exit 1
}
exit 0
