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
Write-Host "=== Results: $($script:PassCount) passed, $($script:FailCount) failed ==="
if ($script:FailCount -gt 0) {
    Write-Host "Failed scenarios:"
    foreach ($n in $script:FailedNames) { Write-Host "  - $n" }
    exit 1
}
exit 0
