#!/usr/bin/env pwsh
<#
.SYNOPSIS
    One-shot migration: back-fills fenced ```yaml blocks into an existing
    docs/spec/assertions.md written in the pre-#59 prose-only format.
.DESCRIPTION
    Mirrors migrate-assertions.sh. Idempotent -- skips any ASSERT-NNNN
    section that already has a yaml block immediately after its heading
    (allowing for a blank line in between). Run once per repo; after that,
    architect.md writes both forms together on every new assertion.
.PARAMETER Path
    Path to assertions.md. Defaults to docs/spec/assertions.md at the repo root.
.EXAMPLE
    pwsh tools/workflow/migrate-assertions.ps1
#>
param(
    [string]$Path
)

$ErrorActionPreference = "Stop"

$root = (git rev-parse --show-toplevel 2>$null)
if (-not $root) { Write-Error "not inside a git repository"; exit 1 }
if (-not $Path) { $Path = Join-Path $root "docs/spec/assertions.md" }
if (-not (Test-Path $Path)) { Write-Error "$Path does not exist"; exit 1 }

# Security-tag heuristic -- mirrors the keywords architect.md's own tagging
# rule names (auth, validation, secrets, error handling). Best-effort: it
# gets a migrated file to a reviewable starting point, not a verified one.
function Test-IsSecurity {
    param([string]$Text)
    return $Text -match '(?i)auth|password|credential|secret|token|permission|valid|sanitiz|inject|session|encrypt'
}

$lines = Get-Content $Path
$out = New-Object System.Collections.Generic.List[string]
$migratedCount = 0
$n = $lines.Count
$i = 0

while ($i -lt $n) {
    $line = $lines[$i]
    $out.Add($line)

    if ($line -match '^### (ASSERT-[0-9]+):') {
        $assertId = $Matches[1]

        $next = if ($i + 1 -lt $n) { $lines[$i + 1] } else { "" }
        if ($next -eq "") { $next = if ($i + 2 -lt $n) { $lines[$i + 2] } else { "" } }

        if ($next -eq '```yaml') {
            $i++
            continue
        }

        $module = ""; $given = ""; $when = ""; $thenVal = ""; $andVal = ""
        $j = $i + 1
        while ($j -lt $n) {
            $peek = $lines[$j]
            if ($peek -match '^### ') { break }
            if ($peek -match '^\*\*Module:\*\*\s*(.*)$') { $module = $Matches[1] }
            elseif ($peek -match '^\*\*Given\*\*\s*(.*)$') { $given = $Matches[1] }
            elseif ($peek -match '^\*\*When\*\*\s*(.*)$') { $when = $Matches[1] }
            elseif ($peek -match '^\*\*Then\*\*\s*(.*)$') { $thenVal = $Matches[1] }
            elseif ($peek -match '^\*\*And\*\*\s*(.*)$') { $andVal = $Matches[1] }
            $j++
        }

        if ($module -or $given) {
            $out.Add("")
            $out.Add('```yaml')
            $out.Add("id: $assertId")
            $out.Add("module: $module")
            if (Test-IsSecurity "$given $when $thenVal $andVal") {
                $out.Add("tags: [security]")
            }
            $out.Add("given: $given")
            $out.Add("when: $when")
            $out.Add("then: $thenVal")
            if ($andVal) { $out.Add("and: $andVal") }
            $out.Add('```')
            $out.Add("")
            $migratedCount++
        }
    }

    $i++
}

Set-Content -Path $Path -Value $out

Write-Host "Migrated $migratedCount assertion(s) in: $Path"
Write-Host "Review the inserted yaml blocks (especially the [security] tag heuristic) before committing."
