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

    # Resuming an already-initialized task: never re-run Initialize-StateFile,
    # which would unconditionally truncate the file and reset Current Phase,
    # Phases Done, Tier, Existing Work, and Blocking Issues back to a blank
    # slate -- exactly the state Conductor Step 1 calls `init` to preserve on
    # resume.
    if ((Test-Path $stateFile) -and (Get-StateField -Path $stateFile -Field "Task") -eq $task) {
        $resumePhase = Get-StateField -Path $stateFile -Field "Current Phase"
        $resumeAgent = if ($resumePhase -eq "DONE") { "" } else { (Get-Phase -PipelineBlock $block -PhaseId $resumePhase).agent }
        [PSCustomObject]@{ phase = $resumePhase; agent = $resumeAgent; branch = $branch; stateFile = $stateFile } | ConvertTo-Json -Compress
        return
    }

    $phaseIds = @(Get-PhaseIds -PipelineBlock $block)
    if ($phaseIds.Count -eq 0) { Fail "pipeline $pipeline has no phases" }
    $firstPhase = $phaseIds[0]
    $firstAgent = (Get-Phase -PipelineBlock $block -PhaseId $firstPhase).agent

    Initialize-StateFile -Path $stateFile -Task $task -Pipeline $pipeline -Branch $branch -FirstPhase $firstPhase

    [PSCustomObject]@{ phase = $firstPhase; agent = $firstAgent; branch = $branch; stateFile = $stateFile } | ConvertTo-Json -Compress
}

# Given a phase (already marked done by the caller) and its parallel
# siblings, checks whether the whole group has now gated clean and, if so,
# advances Current Phase past it. Returns a hashtable
# @{ Advanced = $true/$false; NextId = <id or $null>; OnPass = <value or $null> }.
function Invoke-GroupAdvanceIfComplete {
    param($StateFile, $Block, [string]$PhaseId, [string[]]$Parallel, $PhaseBlock)
    $doneList = @((Get-StatePhasesDone -Path $StateFile) -split ' ' | Where-Object { $_ -ne '' })
    $group = @($PhaseId) + $Parallel
    $groupComplete = $true
    foreach ($id in $group) {
        if ($doneList -notcontains $id) { $groupComplete = $false }
    }
    if (-not $groupComplete) {
        return @{ Advanced = $false; NextId = $null; OnPass = $null }
    }
    $ids = @(Get-PhaseIds -PipelineBlock $Block)
    $maxIdx = -1
    foreach ($id in $group) {
        $idx = [array]::IndexOf($ids, $id)
        if ($idx -gt $maxIdx) { $maxIdx = $idx }
    }
    $nextId = if ($maxIdx -ge 0 -and ($maxIdx + 1) -lt $ids.Count) { $ids[$maxIdx + 1] } else { "DONE" }
    Clear-StatePhasesDone -Path $StateFile
    Set-StateField -Path $StateFile -Field "Current Phase" -Value $nextId
    Set-StateField -Path $StateFile -Field "Status" -Value "in-progress"
    Clear-StateBlockingIssues -Path $StateFile
    $onPass = if ($PhaseBlock.onPass) { $PhaseBlock.onPass } else { $null }
    return @{ Advanced = $true; NextId = $(if ($nextId -ne "DONE") { $nextId } else { $null }); OnPass = $onPass }
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
            $ids = @(Get-PhaseIds -PipelineBlock $Block)
            $idx = [array]::IndexOf($ids, $currentPhase)
            $nextId = if ($idx + 1 -lt $ids.Count) { $ids[$idx + 1] } else { "DONE" }
            Set-StateField -Path $StateFile -Field "Current Phase" -Value $nextId
            return Get-NextPayload -Root $Root -Block $Block -StateFile $StateFile
        }
    }

    $parallel = @(Get-PhaseList -Phase $phase -Field "parallelWith")
    $tier = Get-StateField -Path $StateFile -Field "Tier"

    # Unconditional tier-based skip: mark any not-yet-done member of this
    # stage as done without invoking its agent, if the recorded tier is in
    # its skipOnTier list (e.g. AUDIT/DOCUMENT under tier: minimal).
    if ($tier) {
        $doneList = @((Get-StatePhasesDone -Path $StateFile) -split ' ' | Where-Object { $_ -ne '' })
        foreach ($id in (@($currentPhase) + $parallel)) {
            if ($doneList -contains $id) { continue }
            $idPhase = Get-Phase -PipelineBlock $Block -PhaseId $id
            $idSkip = @(Get-PhaseList -Phase $idPhase -Field "skipOnTier")
            if ($idSkip -contains $tier) {
                Add-StatePhaseDone -Path $StateFile -PhaseId $id
                Add-StateExistingWork -Path $StateFile -Line "${id}: skipped (tier: ${tier}, skipOnTier) -- no agent dispatched, no evidence produced for this phase"
            }
        }
    }

    # If that skip completed the whole stage, advance and re-resolve from
    # the new Current Phase.
    $adv = Invoke-GroupAdvanceIfComplete -StateFile $StateFile -Block $Block -PhaseId $currentPhase -Parallel $parallel -PhaseBlock $phase
    if ($adv.Advanced) {
        return Get-NextPayload -Root $Root -Block $Block -StateFile $StateFile
    }

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
    $pauseWhen = @(Get-PhaseList -Phase $phase -Field "pauseWhen")

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
        $parallel = @(Get-PhaseList -Phase $phase -Field "parallelWith")
        Add-StatePhaseDone -Path $stateFile -PhaseId $phaseId

        $adv = Invoke-GroupAdvanceIfComplete -StateFile $stateFile -Block $block -PhaseId $phaseId -Parallel $parallel -PhaseBlock $phase
        if ($adv.Advanced) {
            $nextPhase = $adv.NextId
            $onPass = $adv.OnPass
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
        $inBlock = $false
        $idMatch = $false
        $result = foreach ($line in $lines) {
            if ($line -match $pattern) {
                $marked = $true
                $line -replace "^- \[ \] ", "- [x] "
                continue
            }
            if ($line -eq '```yaml') { $inBlock = $true; $idMatch = $false; $line; continue }
            if ($line -eq '```') { $inBlock = $false; $line; continue }
            if ($inBlock -and $line -match '^id:\s*(.*)$') {
                $idMatch = ($Matches[1].Trim('"') -eq $task)
                $line
                continue
            }
            if ($inBlock -and $idMatch -and $line -match '^status:\s*') {
                "status: done"
                continue
            }
            $line
        }
        Set-Content -Path $tasksFile -Value $result
    }

    Set-StateField -Path $stateFile -Field "Status" -Value "complete"
    [PSCustomObject]@{ status = "complete"; task = $task; taskMarked = $marked } | ConvertTo-Json -Compress
}

# Reads the inline bracket-list for one domain under .tech-decisions.yml's
# top-level `classify:` key. Missing file or domain -> empty list (no globs),
# so every path for that domain comes back "none" rather than an error.
function Get-ClassifyGlobs {
    param([string]$Path, [string]$Domain)
    if (-not (Test-Path $Path)) { return @() }
    $lines = Get-Content $Path
    $inBlock = $false
    foreach ($line in $lines) {
        if ($line -match '^classify:') { $inBlock = $true; continue }
        if ($inBlock -and $line -match '^[A-Za-z]') { break }
        if ($inBlock -and $line -match "^\s\s${Domain}:\s*(.*)") {
            $raw = $Matches[1] -replace '\s+#.*$', ''
            $raw = $raw.Trim().TrimStart('[').TrimEnd(']')
            if (-not $raw) { return @() }
            return @($raw -split ',' | ForEach-Object { $_.Trim().Trim('"') })
        }
    }
    return @()
}

function Test-PathMatchesDomain {
    param([string]$Path, [string[]]$Globs)
    foreach ($g in $Globs) {
        $pattern = $g -replace '\*\*', '*'
        if ($Path -like $pattern) { return $true }
    }
    return $false
}

# Reads the top-level (not nested) `risk_paths:` inline list from
# .tech-decisions.yml. Missing file or key -> empty list.
function Get-RiskPaths {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $line = Get-Content $Path | Where-Object { $_ -match '^risk_paths:' } | Select-Object -First 1
    if (-not $line) { return @() }
    $raw = ($line -replace '^risk_paths:\s*', '') -replace '\s+#.*$', ''
    $raw = $raw.Trim().TrimStart('[').TrimEnd(']')
    if (-not $raw) { return @() }
    return @($raw -split ',' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ -ne '' })
}

function Invoke-Tier {
    param([string[]]$ArgList)
    $filesChanged = ""; $override = ""; $pipeline = ""
    $paths = @(); $untested = @()
    $i = 0
    while ($i -lt $ArgList.Count) {
        switch ($ArgList[$i]) {
            "--files-changed" { $filesChanged = $ArgList[$i + 1]; $i += 2 }
            "--path" { $paths += $ArgList[$i + 1]; $i += 2 }
            "--untested-module" { $untested += $ArgList[$i + 1]; $i += 2 }
            "--override" { $override = $ArgList[$i + 1]; $i += 2 }
            "--pipeline" { $pipeline = $ArgList[$i + 1]; $i += 2 }
            default { Fail "tier: unknown argument $($ArgList[$i])" }
        }
    }
    if (-not $filesChanged) { Fail "tier: --files-changed is required" }

    $root = Get-RepoRoot
    $techFile = Join-Path $root ".tech-decisions.yml"
    $riskGlobs = @(Get-RiskPaths -Path $techFile)
    $riskHit = $false
    foreach ($p in $paths) {
        if (Test-PathMatchesDomain -Path $p -Globs $riskGlobs) { $riskHit = $true }
    }

    $filesChangedNum = [int]$filesChanged
    $natural = ""; $reason = ""
    if ($riskHit) {
        $natural = "elevated"; $reason = "touches a risk_paths-tagged path"
    } elseif ($filesChangedNum -gt 15) {
        $natural = "elevated"; $reason = "$filesChangedNum files changed (>15)"
    } elseif ($untested.Count -gt 0) {
        $natural = "elevated"; $reason = "no existing tests for: $($untested -join ' ')"
    } elseif ($filesChangedNum -le 3) {
        $natural = "minimal"; $reason = "$filesChangedNum files changed (<=3), no risk paths, tests exist for every touched module"
    } else {
        $natural = "standard"; $reason = "$filesChangedNum files changed, no risk paths or untested modules triggering elevation"
    }

    $final = $natural
    $overridden = $false
    $rejectedOverride = $null
    if ($override) {
        if ($riskHit -and $override -ne "elevated") {
            $rejectedOverride = "cannot override down from elevated: a risk_paths match is a hard rule"
        } else {
            $final = $override
            $overridden = $true
            $reason = "human override from $natural ($reason)"
        }
    }

    $data = Get-PipelinesData -Root $root
    $resolved = if ($pipeline) { Resolve-NamedPipeline -Data $data -Root $root -Pipeline $pipeline } else { Resolve-ActivePipeline -Data $data -Root $root }
    if (Test-Path $resolved.StateFile) {
        Set-StateField -Path $resolved.StateFile -Field "Tier" -Value $final
        Set-StateField -Path $resolved.StateFile -Field "Tier Reason" -Value $reason
    }

    [PSCustomObject]@{ tier = $final; reason = $reason; overridden = $overridden; rejectedOverride = $rejectedOverride } | ConvertTo-Json -Compress
}

function Invoke-Classify {
    param([string[]]$ArgList)
    $task = ""
    $paths = @()
    for ($i = 0; $i -lt $ArgList.Count; $i += 2) {
        switch ($ArgList[$i]) {
            "--task" { $task = $ArgList[$i + 1] }
            "--path" { $paths += $ArgList[$i + 1] }
            default { Fail "classify: unknown argument $($ArgList[$i])" }
        }
    }

    $root = Get-RepoRoot
    $techFile = Join-Path $root ".tech-decisions.yml"

    if ($task) {
        $tasksFile = Join-Path $root ".llm/tasks.md"
        if (Test-Path $tasksFile) {
            $lines = Get-Content $tasksFile
            $pattern = "^- \[[ x]\] $([regex]::Escape($task)) "
            $inBlock = $false
            $block = @()
            foreach ($line in $lines) {
                if ($line -match $pattern) { $inBlock = $true; $block += $line; continue }
                if ($inBlock -and $line -match '^- \[') { break }
                if ($inBlock) { $block += $line }
            }
            foreach ($line in $block) {
                $pathMatches = [regex]::Matches($line, 'docs/spec/[A-Za-z0-9_./*-]+')
                foreach ($m in $pathMatches) { $paths += $m.Value }
            }
        }
    }

    if ($paths.Count -eq 0) {
        [PSCustomObject]@{ domain = "ambiguous"; reason = "no-paths-resolved"; paths = @() } | ConvertTo-Json -Compress
        return
    }

    $frontendGlobs = @(Get-ClassifyGlobs -Path $techFile -Domain "frontend")
    $backendGlobs = @(Get-ClassifyGlobs -Path $techFile -Domain "backend")
    $infraGlobs = @(Get-ClassifyGlobs -Path $techFile -Domain "infrastructure")

    $verdict = ""
    $pathResults = @()
    foreach ($p in $paths) {
        $hits = @()
        if (Test-PathMatchesDomain -Path $p -Globs $frontendGlobs) { $hits += "frontend" }
        if (Test-PathMatchesDomain -Path $p -Globs $backendGlobs) { $hits += "backend" }
        if (Test-PathMatchesDomain -Path $p -Globs $infraGlobs) { $hits += "infrastructure" }

        $pathDomain = if ($hits.Count -eq 0) { "none" } elseif ($hits.Count -gt 1) { "ambiguous" } else { $hits[0] }
        $pathResults += [PSCustomObject]@{ path = $p; domain = $pathDomain }

        if ($pathDomain -ne "none") {
            if (-not $verdict) { $verdict = $pathDomain }
            elseif ($verdict -ne $pathDomain) { $verdict = "ambiguous" }
        }
    }
    if (-not $verdict) { $verdict = "ambiguous" }

    [PSCustomObject]@{ domain = $verdict; paths = $pathResults } | ConvertTo-Json -Compress -Depth 5
}

# Extracts fenced ```yaml blocks from docs/spec/assertions.md, filters by
# module (exact match) and, for security-sensitive agents, by the
# "security" tag.
function Invoke-Context {
    param([string[]]$ArgList)
    $agent = ""; $task = ""; $module = ""
    for ($i = 0; $i -lt $ArgList.Count; $i += 2) {
        switch ($ArgList[$i]) {
            "--agent" { $agent = $ArgList[$i + 1] }
            "--task" { $task = $ArgList[$i + 1] }
            "--module" { $module = $ArgList[$i + 1] }
            default { Fail "context: unknown argument $($ArgList[$i])" }
        }
    }
    if (-not $module) { Fail "context: --module is required" }

    $root = Get-RepoRoot
    $assertionsFile = Join-Path $root "docs/spec/assertions.md"
    $requireSecurity = ($agent -eq "security-reviewer") -or ($agent -eq "Security Reviewer")

    $results = @()
    if (Test-Path $assertionsFile) {
        $lines = Get-Content $assertionsFile
        $inBlock = $false
        $current = $null
        foreach ($line in $lines) {
            if ($line -eq '```yaml') {
                $inBlock = $true
                $current = @{ id = ""; module = ""; tags = ""; given = ""; when = ""; then = ""; and = ""; requirementRef = "" }
                continue
            }
            if ($line -eq '```') {
                if ($inBlock) {
                    $inBlock = $false
                    if ($current.module -eq $module) {
                        $hasSecurity = $current.tags -match "security"
                        if (-not $requireSecurity -or $hasSecurity) {
                            $results += [PSCustomObject]$current
                        }
                    }
                }
                continue
            }
            if (-not $inBlock) { continue }
            if ($line -match '^id:\s*(.*)$') { $current.id = $Matches[1] }
            elseif ($line -match '^module:\s*(.*)$') { $current.module = $Matches[1] }
            elseif ($line -match '^tags:\s*(.*)$') { $current.tags = $Matches[1] }
            elseif ($line -match '^given:\s*(.*)$') { $current.given = $Matches[1] }
            elseif ($line -match '^when:\s*(.*)$') { $current.when = $Matches[1] }
            elseif ($line -match '^then:\s*(.*)$') { $current.then = $Matches[1] }
            elseif ($line -match '^and:\s*(.*)$') { $current.and = $Matches[1] }
            elseif ($line -match '^requirementRef:\s*(.*)$') { $current.requirementRef = $Matches[1] }
        }
    }

    [PSCustomObject]@{ module = $module; assertions = $results } | ConvertTo-Json -Compress -Depth 5
}

# Strips a YAML inline-list `[a, b]` or `["a", "b"]` down to a comma-joined,
# unquoted, trimmed scalar list (empty string if the list is empty).
function Get-InlineListString {
    param([string]$Raw)
    $trimmed = $Raw.Trim().TrimStart('[').TrimEnd(']')
    if (-not $trimmed) { return "" }
    $items = $trimmed -split ',' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ -ne '' }
    return ($items -join ',')
}

function Invoke-TasksNext {
    $root = Get-RepoRoot
    $tasksFile = Join-Path $root ".llm/tasks.md"
    if (-not (Test-Path $tasksFile)) {
        [PSCustomObject]@{ task = $null; reason = "no-tasks-file" } | ConvertTo-Json -Compress
        return
    }

    $lines = Get-Content $tasksFile
    $tasks = [ordered]@{}
    $inBlock = $false
    $current = $null
    foreach ($line in $lines) {
        if ($line -eq '```yaml') {
            $inBlock = $true
            $current = @{ id = ""; title = ""; deps = ""; criticality = ""; specRefs = ""; status = ""; domain = "" }
            continue
        }
        if ($line -eq '```') {
            if ($inBlock -and $current.id) {
                $current.deps = Get-InlineListString $current.deps
                $current.specRefs = Get-InlineListString $current.specRefs
                $tasks[$current.id] = $current
            }
            $inBlock = $false
            continue
        }
        if (-not $inBlock) { continue }
        if ($line -match '^id:\s*(.*)$') { $current.id = $Matches[1].Trim('"') }
        elseif ($line -match '^title:\s*(.*)$') { $current.title = $Matches[1].Trim('"') }
        elseif ($line -match '^deps:\s*(.*)$') { $current.deps = $Matches[1] }
        elseif ($line -match '^criticality:\s*(.*)$') { $current.criticality = $Matches[1] }
        elseif ($line -match '^specRefs:\s*(.*)$') { $current.specRefs = $Matches[1] }
        elseif ($line -match '^status:\s*(.*)$') { $current.status = $Matches[1] }
        elseif ($line -match '^domain:\s*(.*)$') { $current.domain = $Matches[1] }
    }

    if ($tasks.Count -eq 0) {
        [PSCustomObject]@{ task = $null; reason = "no-structured-tasks" } | ConvertTo-Json -Compress
        return
    }

    # Cycle detection (DFS, 0=unvisited 1=visiting 2=done) before picking "next".
    $mark = @{}
    $cyclePath = $null
    function Test-Cycle {
        param([string]$NodeId, [string]$Path)
        $state = if ($mark.ContainsKey($NodeId)) { $mark[$NodeId] } else { 0 }
        if ($state -eq 2) { return $true }
        if ($state -eq 1) { $script:cyclePath = "$Path -> $NodeId"; return $false }
        $mark[$NodeId] = 1
        $depsStr = $tasks[$NodeId].deps
        if ($depsStr) {
            foreach ($dep in ($depsStr -split ',')) {
                if (-not $tasks.Contains($dep)) { continue }
                if (-not (Test-Cycle -NodeId $dep -Path "$Path -> $NodeId")) { return $false }
            }
        }
        $mark[$NodeId] = 2
        return $true
    }
    foreach ($id in $tasks.Keys) {
        if (-not $mark.ContainsKey($id) -or $mark[$id] -eq 0) {
            if (-not (Test-Cycle -NodeId $id -Path "")) {
                $clean = $script:cyclePath -replace '^ -> ', ''
                [PSCustomObject]@{ task = $null; reason = "cycle-detected"; cycle = $clean } | ConvertTo-Json -Compress
                return
            }
        }
    }

    foreach ($id in $tasks.Keys) {
        $t = $tasks[$id]
        if ($t.status -eq "done" -or $t.status -eq "blocked") { continue }
        $allDepsDone = $true
        if ($t.deps) {
            foreach ($dep in ($t.deps -split ',')) {
                if (-not $tasks.Contains($dep) -or $tasks[$dep].status -ne "done") {
                    $allDepsDone = $false
                    break
                }
            }
        }
        if ($allDepsDone) {
            [PSCustomObject]@{ task = [PSCustomObject]$t } | ConvertTo-Json -Compress -Depth 5
            return
        }
    }

    [PSCustomObject]@{ task = $null; reason = "none-ready" } | ConvertTo-Json -Compress
}

switch ($Command) {
    "init" { Invoke-Init -ArgList $Rest }
    "next" { Invoke-Next -ArgList $Rest }
    "gate" { Invoke-Gate -ArgList $Rest }
    "complete" { Invoke-Complete -ArgList $Rest }
    "classify" { Invoke-Classify -ArgList $Rest }
    "context" { Invoke-Context -ArgList $Rest }
    "tasks" {
        if ($Rest.Count -lt 1 -or $Rest[0] -ne "next") { Fail "tasks: usage: workflow.ps1 tasks next" }
        Invoke-TasksNext
    }
    "tier" { Invoke-Tier -ArgList $Rest }
    default { Fail "unknown command: $Command" }
}
