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

function Set-StateField {
    param([string]$Path, [string]$Field, [string]$Value)
    $lines = Get-Content $Path
    $pattern = "^\*\*$([regex]::Escape($Field)):\*\*"
    $found = $false
    $result = foreach ($line in $lines) {
        if ($line -match $pattern) {
            "**${Field}:** ${Value}"
            $found = $true
        } else {
            $line
        }
    }
    if (-not $found) {
        $result += "**${Field}:** ${Value}"
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
[Not yet extracted — filled by the conductor/Tech Lead, not this engine]

## Toolchain
[Not yet extracted]

## Relevant Assertions
[Not yet extracted]

## Interface Contract
[Not yet extracted]

## Catalog Slice
[Not yet extracted]

## Security Rules
[Not yet extracted]

## Existing Work
[None yet]

## Blocking Issues
[None]
"@
    Set-Content -Path $Path -Value $content
}
