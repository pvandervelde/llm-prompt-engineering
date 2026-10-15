#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Workflow engine (PowerShell) -- deterministic branch resolution, phase
    sequencing, and gate evaluation for the pipelines defined in
    workflow/pipelines.yml.
.DESCRIPTION
    Mirrors workflow.sh command-for-command; see workflow/README.md for the
    pipeline schema and tools/workflow/README.md for the CLI contract.
    Requires the powershell-yaml module: Install-Module powershell-yaml
#>
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = "Stop"
Import-Module powershell-yaml -ErrorAction Stop

. (Join-Path $PSScriptRoot "lib/State.ps1")

$ValidReasons = @("spec-gap", "blocked", "safety-critical-survivor", "formal-counterexample", "critical-finding", "fail")

function Fail {
    param([string]$Message)
    [PSCustomObject]@{ error = $Message } | ConvertTo-Json -Compress
    exit 1
}

function Get-RepoRoot {
    $root = git rev-parse --show-toplevel 2>$null
    if (-not $root) { Fail "not inside a git repository" }
    return $root.Trim()
}

function Get-PipelinesData {
    param([string]$Root)
    $path = Join-Path $Root "workflow/pipelines.yml"
    if (-not (Test-Path $path)) { Fail "workflow/pipelines.yml not found" }
    return ConvertFrom-Yaml (Get-Content $path -Raw)
}

function Get-PipelineBlock {
    param($Data, [string]$Pipeline)
    $block = $Data.pipelines.$Pipeline
    if (-not $block) { Fail "unknown pipeline: $Pipeline" }
    return $block
}

function Get-PhaseIds {
    param($PipelineBlock)
    return @($PipelineBlock.phases | ForEach-Object { $_.id })
}

function Get-Phase {
    param($PipelineBlock, [string]$PhaseId)
    return $PipelineBlock.phases | Where-Object { $_.id -eq $PhaseId } | Select-Object -First 1
}

function Get-PhaseList {
    param($Phase, [string]$Field)
    if (-not $Phase.$Field) { return @() }
    return @($Phase.$Field)
}

# ---- pipeline/state resolution --------------------------------------------

function Resolve-NamedPipeline {
    param($Data, [string]$Root, [string]$Pipeline)
    $block = Get-PipelineBlock -Data $Data -Pipeline $Pipeline
    $stateFile = Join-Path $Root $block.stateFile
    return [PSCustomObject]@{ Name = $Pipeline; StateFile = $stateFile; Block = $block }
}

function Resolve-ActivePipeline {
    param($Data, [string]$Root)
    $candidates = @()
    foreach ($name in @("software", "infrastructure")) {
        $block = Get-PipelineBlock -Data $Data -Pipeline $name
        $stateFile = Join-Path $Root $block.stateFile
        if (Test-Path $stateFile) {
            $status = Get-StateField -Path $stateFile -Field "Status"
            if ($status -ne "complete") {
                $candidates += [PSCustomObject]@{ Name = $name; StateFile = $stateFile; Block = $block }
            }
        }
    }
    if ($candidates.Count -eq 0) { Fail "no active task; run 'init' first or pass --pipeline" }
    if ($candidates.Count -gt 1) { Fail "multiple active pipelines ($(($candidates.Name) -join ', ')); pass --pipeline to disambiguate" }
    return $candidates[0]
}

# ---- branch resolution (tech-lead.md Step 2b, infra-lead.md equivalent) --

function Get-Slug {
    param([string]$Task, [string]$Slug)
    if ($Slug) { return $Slug }
    $s = $Task.ToLowerInvariant()
    $s = [regex]::Replace($s, '[^a-z0-9]+', '-')
    $s = $s.Trim('-')
    return $s
}

function Test-IntegrationBranch {
    param([string]$Branch)
    return ($Branch -in @("main", "master", "develop")) -or ($Branch -like "release/*")
}

function Resolve-Branch {
    param([string]$Task, [string]$Prefix, [string]$StateFile, [string]$Slug)
    $current = (git branch --show-current).Trim()

    $existingTask = ""
    if (Test-Path $StateFile) {
        $existingTask = Get-StateField -Path $StateFile -Field "Task"
    }

    if ($current.StartsWith($Prefix)) {
        if ($existingTask -and $existingTask -ne $Task) {
            return [PSCustomObject]@{ Action = "ask"; Reason = "wrong-task-branch"; Current = $current }
        }
        return [PSCustomObject]@{ Action = "use"; Branch = $current }
    }

    if (Test-IntegrationBranch -Branch $current) {
        $newBranch = "${Prefix}$(Get-Slug -Task $Task -Slug $Slug)"
        return [PSCustomObject]@{ Action = "create"; Branch = $newBranch }
    }

    return [PSCustomObject]@{ Action = "ask"; Reason = "ambiguous-branch"; Current = $current }
}

# ---- SPEC_REVIEW_GATE skip check ------------------------------------------

function Test-SpecReviewFresh {
    param([string]$Root, [string]$RequiredVerdict, [string]$WatchPath)
    $reportDir = Join-Path $Root ".llm/spec-review"
    if (-not (Test-Path $reportDir)) { return $false }
    $report = Get-ChildItem -Path $reportDir -Filter "*.md" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
    if (-not $report) { return $false }

    $lines = Get-Content $report.FullName
    $idx = [array]::IndexOf($lines, "## Verdict")
    if ($idx -lt 0 -or $idx + 1 -ge $lines.Count) { return $false }
    $verdict = $lines[$idx + 1].Trim()
    if ($verdict -ne $RequiredVerdict) { return $false }

    $reportMtime = [int64](Get-Date $report.LastWriteTimeUtc -UFormat %s)
    Push-Location $Root
    try {
        $specCommitRaw = git log -1 --format=%ct -- $WatchPath 2>$null
    } finally {
        Pop-Location
    }
    $specCommitEpoch = 0
    if ($specCommitRaw) { $specCommitEpoch = [int64]$specCommitRaw.Trim() }
    return $reportMtime -ge $specCommitEpoch
}

# ---- commands --------------------------------------------------------------

function Invoke-Init {
    param([string[]]$ArgList)
    $task = ""; $pipeline = ""; $slug = ""
    for ($i = 0; $i -lt $ArgList.Count; $i += 2) {
        switch ($ArgList[$i]) {
            "--task" { $task = $ArgList[$i + 1] }
            "--pipeline" { $pipeline = $ArgList[$i + 1] }
            "--slug" { $slug = $ArgList[$i + 1] }
            default { Fail "init: unknown argument $($ArgList[$i])" }
        }
    }
    if (-not $task) { Fail "init: --task is required" }
    if (-not $pipeline) { Fail "init: --pipeline is required" }

    $root = Get-RepoRoot
    $data = Get-PipelinesData -Root $root
    $block = Get-PipelineBlock -Data $data -Pipeline $pipeline
    $stateFile = Join-Path $root $block.stateFile

    $resolution = Resolve-Branch -Task $task -Prefix $block.branchPrefix -StateFile $stateFile -Slug $slug

    switch ($resolution.Action) {
        "ask" {
            [PSCustomObject]@{ action = "ask"; reason = $resolution.Reason; currentBranch = $resolution.Current } | ConvertTo-Json -Compress
            exit 2
        }
        "create" {
            Push-Location $root
            try {
                git switch -c $resolution.Branch *>$null
                if ($LASTEXITCODE -ne 0) { git switch $resolution.Branch *>$null }
            } finally {
                Pop-Location
            }
            $branch = $resolution.Branch
        }
        "use" {
            $branch = $resolution.Branch
        }
    }

    $phaseIds = Get-PhaseIds -PipelineBlock $block
    if ($phaseIds.Count -eq 0) { Fail "pipeline $pipeline has no phases" }
    $firstPhase = $phaseIds[0]
    $firstAgent = (Get-Phase -PipelineBlock $block -PhaseId $firstPhase).agent

    Initialize-StateFile -Path $stateFile -Task $task -Pipeline $pipeline -Branch $branch -FirstPhase $firstPhase

    [PSCustomObject]@{ phase = $firstPhase; agent = $firstAgent; branch = $branch; stateFile = $stateFile } | ConvertTo-Json -Compress
}

function Get-NextPayload {
    param($Root, $Block, [string]$StateFile)
    $currentPhase = Get-StateField -Path $StateFile -Field "Current Phase"
    $status = Get-StateField -Path $StateFile -Field "Status"

    if ($currentPhase -eq "DONE" -or $status -eq "complete") {
        return [PSCustomObject]@{ phases = @(); status = "complete"; contextRefs = @($StateFile) }
    }

    $phase = Get-Phase -PipelineBlock $Block -PhaseId $currentPhase
    if (-not $phase) { Fail "state file names unknown phase: $currentPhase" }

    if ($phase.advance -eq "conditional") {
        $reqVerdict = $phase.skipWhen.reportVerdict
        $watchPath = $phase.skipWhen.reportNewerThan
        if (Test-SpecReviewFresh -Root $Root -RequiredVerdict $reqVerdict -WatchPath $watchPath) {
            $ids = Get-PhaseIds -PipelineBlock $Block
            $idx = [array]::IndexOf($ids, $currentPhase)
            $nextId = if ($idx + 1 -lt $ids.Count) { $ids[$idx + 1] } else { "DONE" }
            Set-StateField -Path $StateFile -Field "Current Phase" -Value $nextId
            return Get-NextPayload -Root $Root -Block $Block -StateFile $StateFile
        }
    }

    $parallel = Get-PhaseList -Phase $phase -Field "parallelWith"
    $doneList = @((Get-StatePhasesDone -Path $StateFile) -split ' ' | Where-Object { $_ -ne '' })

    $pending = @()
    foreach ($id in (@($currentPhase) + $parallel)) {
        if ($doneList -contains $id) { continue }
        $agent = (Get-Phase -PipelineBlock $Block -PhaseId $id).agent
        $pending += [PSCustomObject]@{ phase = $id; agent = $agent }
    }

    return [PSCustomObject]@{ phases = $pending; contextRefs = @($StateFile) }
}

function Invoke-Next {
    param([string[]]$ArgList)
    $pipeline = ""
    for ($i = 0; $i -lt $ArgList.Count; $i += 2) {
        switch ($ArgList[$i]) {
            "--pipeline" { $pipeline = $ArgList[$i + 1] }
            default { Fail "next: unknown argument $($ArgList[$i])" }
        }
    }

    $root = Get-RepoRoot
    $data = Get-PipelinesData -Root $root
    $resolved = if ($pipeline) { Resolve-NamedPipeline -Data $data -Root $root -Pipeline $pipeline } else { Resolve-ActivePipeline -Data $data -Root $root }
    if (-not (Test-Path $resolved.StateFile)) { Fail "no state file for $($resolved.Name); run 'init' first" }

    Get-NextPayload -Root $root -Block $resolved.Block -StateFile $resolved.StateFile | ConvertTo-Json -Compress
}

function Invoke-Gate {
    param([string[]]$ArgList)
    $pipeline = ""; $phaseId = ""; $verdict = ""; $actual = ""; $target = ""
    $reasons = @()
    $i = 0
    while ($i -lt $ArgList.Count) {
        switch ($ArgList[$i]) {
            "--pipeline" { $pipeline = $ArgList[$i + 1]; $i += 2 }
            "--phase" { $phaseId = $ArgList[$i + 1]; $i += 2 }
            "--verdict" { $verdict = $ArgList[$i + 1]; $i += 2 }
            "--reason" { $reasons += $ArgList[$i + 1]; $i += 2 }
            "--actual" { $actual = $ArgList[$i + 1]; $i += 2 }
            "--target" { $target = $ArgList[$i + 1]; $i += 2 }
            default { Fail "gate: unknown argument $($ArgList[$i])" }
        }
    }
    if (-not $phaseId) { Fail "gate: --phase is required" }
    if (-not $verdict) { Fail "gate: --verdict is required" }

    foreach ($r in $reasons) {
        if ($ValidReasons -notcontains $r) {
            Fail "gate: unrecognized --reason '$r' (see workflow/README.md for the fixed set)"
        }
    }

    $root = Get-RepoRoot
    $data = Get-PipelinesData -Root $root
    $resolved = if ($pipeline) { Resolve-NamedPipeline -Data $data -Root $root -Pipeline $pipeline } else { Resolve-ActivePipeline -Data $data -Root $root }
    if (-not (Test-Path $resolved.StateFile)) { Fail "no state file for $($resolved.Name); run 'init' first" }
    $stateFile = $resolved.StateFile
    $block = $resolved.Block

    $phase = Get-Phase -PipelineBlock $block -PhaseId $phaseId
    if (-not $phase) { Fail "unknown phase: $phaseId" }
    $pauseWhen = Get-PhaseList -Phase $phase -Field "pauseWhen"

    $result = "ADVANCE"
    $blockingReason = ""

    if ($actual -ne "" -and $target -ne "") {
        if ([double]$actual -lt [double]$target) {
            $result = "FAIL"
            $blockingReason = "threshold-unmet (actual=$actual < target=$target)"
        }
    }

    if ($result -eq "ADVANCE") {
        foreach ($r in $reasons) {
            if ($pauseWhen -contains $r) {
                $result = "PAUSE"
                $blockingReason = $r
                break
            }
        }
    }

    $workNote = "${phaseId}: verdict=${verdict} result=${result}"
    if ($blockingReason) { $workNote += " ($blockingReason)" }
    Add-StateExistingWork -Path $stateFile -Line $workNote

    $nextPhase = $null
    $onPass = $null

    if ($result -eq "ADVANCE") {
        $parallel = Get-PhaseList -Phase $phase -Field "parallelWith"
        Add-StatePhaseDone -Path $stateFile -PhaseId $phaseId
        $doneList = @((Get-StatePhasesDone -Path $stateFile) -split ' ' | Where-Object { $_ -ne '' })

        $group = @($phaseId) + $parallel
        $groupComplete = $true
        foreach ($id in $group) {
            if ($doneList -notcontains $id) { $groupComplete = $false }
        }

        if ($groupComplete) {
            $ids = Get-PhaseIds -PipelineBlock $block
            $maxIdx = -1
            foreach ($id in $group) {
                $idx = [array]::IndexOf($ids, $id)
                if ($idx -gt $maxIdx) { $maxIdx = $idx }
            }
            $nextId = if ($maxIdx -ge 0 -and ($maxIdx + 1) -lt $ids.Count) { $ids[$maxIdx + 1] } else { "DONE" }

            Clear-StatePhasesDone -Path $stateFile
            Set-StateField -Path $stateFile -Field "Current Phase" -Value $nextId
            Set-StateField -Path $stateFile -Field "Status" -Value "in-progress"
            Clear-StateBlockingIssues -Path $stateFile
            if ($nextId -ne "DONE") { $nextPhase = $nextId }
            if ($phase.onPass) { $onPass = $phase.onPass }
        } else {
            $nextPhase = $phaseId
        }
    } else {
        Set-StateField -Path $stateFile -Field "Status" -Value "paused"
        Add-StateBlockingIssue -Path $stateFile -Line "**[$phaseId]** $blockingReason"
    }

    [PSCustomObject]@{ result = $result; nextPhase = $nextPhase; onPass = $onPass } | ConvertTo-Json -Compress
}

function Invoke-Complete {
    param([string[]]$ArgList)
    $task = ""; $pipeline = ""
    for ($i = 0; $i -lt $ArgList.Count; $i += 2) {
        switch ($ArgList[$i]) {
            "--task" { $task = $ArgList[$i + 1] }
            "--pipeline" { $pipeline = $ArgList[$i + 1] }
            default { Fail "complete: unknown argument $($ArgList[$i])" }
        }
    }
    if (-not $task) { Fail "complete: --task is required" }

    $root = Get-RepoRoot
    $data = Get-PipelinesData -Root $root
    $resolved = if ($pipeline) { Resolve-NamedPipeline -Data $data -Root $root -Pipeline $pipeline } else { Resolve-ActivePipeline -Data $data -Root $root }
    if (-not (Test-Path $resolved.StateFile)) { Fail "no state file for $($resolved.Name); run 'init' first" }
    $stateFile = $resolved.StateFile

    $currentPhase = Get-StateField -Path $stateFile -Field "Current Phase"
    if ($currentPhase -ne "DONE") { Fail "pipeline not finished (current phase: $currentPhase)" }

    $marked = $false
    $tasksFile = Join-Path $root ".llm/tasks.md"
    if (Test-Path $tasksFile) {
        $lines = Get-Content $tasksFile
        $pattern = "^- \[ \] $([regex]::Escape($task)) "
        $result = foreach ($line in $lines) {
            if ($line -match $pattern) {
                $line -replace "^- \[ \] ", "- [x] "
                $marked = $true
            } else {
                $line
            }
        }
        if ($marked) { Set-Content -Path $tasksFile -Value $result }
    }

    Set-StateField -Path $stateFile -Field "Status" -Value "complete"
    [PSCustomObject]@{ status = "complete"; task = $task; taskMarked = $marked } | ConvertTo-Json -Compress
}

switch ($Command) {
    "init" { Invoke-Init -ArgList $Rest }
    "next" { Invoke-Next -ArgList $Rest }
    "gate" { Invoke-Gate -ArgList $Rest }
    "complete" { Invoke-Complete -ArgList $Rest }
    default { Fail "unknown command: $Command" }
}
