# Read/write helpers for the workflow state file's machine-managed header.
# Mirrors lib/state.sh function-for-function. The header is a fixed set of
# "**Field:** value" lines plus a "## Existing Work" / "## Blocking Issues"
# section this engine appends to. Everything else in the file (Standards,
# Context Bundle, etc.) is written by the conductor/agent, never by this
# engine, and these functions never touch it.

function Get-StateField {
    param([string]$Path, [string]$Field)
    if (-not (Test-Path $Path)) { return "" }
    $line = Get-Content $Path | Where-Object { $_ -match "^\*\*$([regex]::Escape($Field)):\*\*" } | Select-Object -First 1
    if (-not $line) { return "" }
    return ($line -replace "^\*\*$([regex]::Escape($Field)):\*\*\s*", "")
}

# Replaces (or inserts, if missing) a **Field:** line. A missing field is
# inserted right before the first "## " heading (end of the header block),
# never appended at EOF -- EOF may be inside or after a section whose own
# rewrite logic (e.g. Clear-StateBlockingIssues) assumes nothing meaningful
# follows it.
function Set-StateField {
    param([string]$Path, [string]$Field, [string]$Value)
    $lines = Get-Content $Path
    $pattern = "^\*\*$([regex]::Escape($Field)):\*\*"
    $found = $false
    $inserted = $false
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line -match $pattern) {
            $result.Add("**${Field}:** ${Value}")
            $found = $true
            continue
        }
        if (-not $found -and -not $inserted -and $line -like "## *") {
            $result.Add("**${Field}:** ${Value}")
            $inserted = $true
        }
        $result.Add($line)
    }
    if (-not $found -and -not $inserted) {
        $result.Add("**${Field}:** ${Value}")
    }
    Set-Content -Path $Path -Value $result
}

function Get-StatePhasesDone {
    param([string]$Path)
    return Get-StateField -Path $Path -Field "Phases Done"
}

function Add-StatePhaseDone {
    param([string]$Path, [string]$PhaseId)
    $current = Get-StatePhasesDone -Path $Path
    $items = @($current -split ' ' | Where-Object { $_ -ne '' })
    if ($items -notcontains $PhaseId) {
        $items += $PhaseId
    }
    Set-StateField -Path $Path -Field "Phases Done" -Value ($items -join ' ')
}

function Clear-StatePhasesDone {
    param([string]$Path)
    Set-StateField -Path $Path -Field "Phases Done" -Value ""
}

function Add-StateExistingWork {
    param([string]$Path, [string]$Line)
    $lines = Get-Content $Path
    $result = New-Object System.Collections.Generic.List[string]
    $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $result.Add($lines[$i])
        if (-not $done -and $lines[$i] -eq "## Existing Work") {
            $next = if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { "" }
            if ($next -ne "[None yet]" -and $next -ne "") {
                $result.Add($next)
                $i++
            } elseif ($next -eq "[None yet]") {
                $i++
            }
            $result.Add("- ${Line}")
            $done = $true
        }
    }
    Set-Content -Path $Path -Value $result
}

function Add-StateBlockingIssue {
    param([string]$Path, [string]$Line)
    $lines = Get-Content $Path
    $result = New-Object System.Collections.Generic.List[string]
    $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $result.Add($lines[$i])
        if (-not $done -and $lines[$i] -eq "## Blocking Issues") {
            $next = if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { "" }
            if ($next -ne "[None]" -and $next -ne "") {
                $result.Add($next)
                $i++
            } elseif ($next -eq "[None]") {
                $i++
            }
            $result.Add("- ${Line}")
            $done = $true
        }
    }
    Set-Content -Path $Path -Value $result
}

function Clear-StateBlockingIssues {
    param([string]$Path)
    $lines = Get-Content $Path
    $result = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($line in $lines) {
        if ($line -eq "## Blocking Issues") {
            $result.Add($line)
            $result.Add("[None]")
            $skip = $true
            continue
        }
        if ($skip) {
            if ($line -like "## *") {
                $skip = $false
            } else {
                continue
            }
        }
        $result.Add($line)
    }
    Set-Content -Path $Path -Value $result
}

# Returns the recorded "<mode> (<source>)" string for one phase under
# "## Isolation", or "" if that phase's isolation mode hasn't been resolved
# yet for this task.
function Get-StateIsolation {
    param([string]$Path, [string]$PhaseId)
    if (-not (Test-Path $Path)) { return "" }
    $lines = Get-Content $Path
    $inSection = $false
    foreach ($line in $lines) {
        if ($line -eq "## Isolation") { $inSection = $true; continue }
        if ($inSection -and $line -like "## *") { break }
        if ($inSection -and $line -match "^$([regex]::Escape($PhaseId)): (.*)$") {
            return $Matches[1]
        }
    }
    return ""
}

# Upserts one "<phase>: <mode> (<source>)" line under "## Isolation" --
# replacing that phase's existing line if present, replacing a lone
# "[None yet]" placeholder on first use, or appending otherwise. Mirrors
# state_isolation_set in lib/state.sh function-for-function.
function Set-StateIsolation {
    param([string]$Path, [string]$PhaseId, [string]$Mode, [string]$Source)
    $newLine = "${PhaseId}: ${Mode} (${Source})"
    $lines = Get-Content $Path
    $result = New-Object System.Collections.Generic.List[string]
    $inSection = $false
    $replaced = $false
    $sectionSeen = $false
    $pattern = "^$([regex]::Escape($PhaseId)): "
    foreach ($line in $lines) {
        if ($line -eq "## Isolation") {
            $result.Add($line)
            $inSection = $true
            $sectionSeen = $true
            continue
        }
        if ($inSection -and $line -like "## *") {
            if (-not $replaced) { $result.Add($newLine); $replaced = $true }
            $inSection = $false
            $result.Add($line)
            continue
        }
        if ($inSection -and $line -eq "[None yet]") { continue }
        if ($inSection -and $line -match $pattern) {
            $result.Add($newLine)
            $replaced = $true
            continue
        }
        $result.Add($line)
    }
    if ($sectionSeen -and -not $replaced) {
        $result.Add($newLine)
    }
    Set-Content -Path $Path -Value $result
}

function Initialize-StateFile {
    param([string]$Path, [string]$Task, [string]$Pipeline, [string]$Branch, [string]$FirstPhase)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $content = @"
# Workflow State — ${Task}

**Task:** ${Task}
**Pipeline:** ${Pipeline}
**Branch:** ${Branch}
**Current Phase:** ${FirstPhase}
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
"@
    Set-Content -Path $Path -Value $content
}
