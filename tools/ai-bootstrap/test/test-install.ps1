#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Self-contained, dependency-free end-to-end test harness for
    tools/ai-bootstrap/install.ps1 (issue #68).
.DESCRIPTION
    No Pester, no external test-framework dependency - this repo validates
    its shell/PowerShell tooling by actually running it against a scratch
    environment, not by reading generated output or adopting a
    test-framework dependency.

    Mirrors test-install.sh scenario-for-scenario for contract parity
    between the bash and PowerShell implementations.
.EXAMPLE
    pwsh ./tools/ai-bootstrap/test/test-install.ps1

    Scenario matrix (kept in sync with test-install.sh):

      Tier 1 - specification / happy path
        01 Test-HappyPathCreatesDestinationDirs
        02 Test-AgentsCopiedToCopilotWithExactContent
        03 Test-ClaudeAgentsCopiedToClaudeWithExactContent
        04 Test-DestinationFileCountsMatchSourceExactly
        05 Test-ExitCodeZeroOnSuccess
        06 Test-CopilotHomeOverrideRedirectsDestination
        07 Test-MissingSkillsDirSkippedSilently
        08 Test-SkillsDirCopiedToBothTargetsWhenPresent
        09 Test-NestedDestinationDirsCreatedFromEmptyHome

      Tier 2 - adversarial / boundary
        10 Test-NoForceSkipsExistingFileWithoutOverwrite
        11 Test-NoForcePrintsNoticeForSkippedFile
        12 Test-ForceOverwritesExistingFile
        13 Test-PartialPreexistingMixedForceOff
        14 Test-IdempotentRerunWithoutForce
        15 Test-IdempotentRerunWithForceX3
        16 Test-ByteForByteStubKillerAllTargets
        17 Test-RepoRootResolvedFromCwdNotScriptLocation
        18 Test-InvocationOutsideAnyGitRepoFailsNonZero
        19 Test-NoWritesOutsideDestinationTree
        20 Test-SourceRepoUntouchedAfterInstall
        21 Test-DestinationPathWithSpacesIsHandled
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Locate the real repo + the script under test
# ---------------------------------------------------------------------------
$thisDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$realRepoRoot = $null
try
{
    $realRepoRoot = (& git -C $thisDir rev-parse --show-toplevel 2>$null)
}
catch
{
    $realRepoRoot = $null
}

if (-not $realRepoRoot)
{
    Write-Host "FATAL: cannot resolve the real repo root via git from $thisDir" -ForegroundColor Red
    exit 1
}

$installPs1 = Join-Path $realRepoRoot "tools/ai-bootstrap/install.ps1"

if (-not (Test-Path $installPs1))
{
    Write-Host "NOTICE: $installPs1 does not exist yet. Scenarios below are expected" -ForegroundColor Yellow
    Write-Host "        to fail until install.ps1 is implemented (TDD RED phase)." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Scratch root
# ---------------------------------------------------------------------------
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("install-ps1-test-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 12))
New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null

function Remove-Scratch
{
    if (Test-Path $scratchRoot)
    {
        Remove-Item -Path $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Counters / reporting
# ---------------------------------------------------------------------------
$script:TestsRun = 0
$script:TestsPassed = 0
$script:Failures = @()

function Write-Note
{
    param([string]$Message)
    Write-Host "    -> $Message" -ForegroundColor DarkYellow
}

function Invoke-Case
{
    param([string]$Name, [scriptblock]$Case)
    $script:TestsRun++
    $ok = $false
    try
    {
        $ok = & $Case
    }
    catch
    {
        Write-Note "unhandled exception: $_"
        $ok = $false
    }

    if ($ok)
    {
        $script:TestsPassed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    else
    {
        $script:Failures += $Name
        Write-Host "[FAIL] $Name" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# Generic assertion helpers
# ---------------------------------------------------------------------------
function Assert-FileExists
{
    param([string]$Path)
    if (-not (Test-Path $Path -PathType Leaf))
    {
        Write-Note "expected file to exist: $Path"
        return $false
    }
    return $true
}

function Assert-DirAbsent
{
    param([string]$Path)
    if (Test-Path $Path -PathType Container)
    {
        Write-Note "expected directory to NOT exist: $Path"
        return $false
    }
    return $true
}

function Assert-FilesEqual
{
    param([string]$ActualPath, [string]$ExpectedPath)
    if (-not (Test-Path $ActualPath -PathType Leaf))
    {
        Write-Note "actual file missing: $ActualPath"
        return $false
    }
    $actualBytes = [System.IO.File]::ReadAllBytes($ActualPath)
    $expectedBytes = [System.IO.File]::ReadAllBytes($ExpectedPath)
    if ($actualBytes.Length -ne $expectedBytes.Length)
    {
        Write-Note "content length mismatch between $ActualPath and $ExpectedPath"
        return $false
    }
    for ($i = 0; $i -lt $actualBytes.Length; $i++)
    {
        if ($actualBytes[$i] -ne $expectedBytes[$i])
        {
            Write-Note "content mismatch between $ActualPath and $ExpectedPath at byte $i"
            return $false
        }
    }
    return $true
}

function Assert-FileContent
{
    param([string]$Path, [string]$ExpectedContent)
    if (-not (Test-Path $Path -PathType Leaf))
    {
        Write-Note "file missing: $Path"
        return $false
    }
    $actual = (Get-Content -Path $Path -Raw).TrimEnd("`r", "`n")
    if ($actual -ne $ExpectedContent)
    {
        Write-Note "content mismatch in $Path`: expected [$ExpectedContent] got [$actual]"
        return $false
    }
    return $true
}

function Count-Files
{
    param([string]$Dir)
    if (-not (Test-Path $Dir -PathType Container))
    {
        return 0
    }
    return @(Get-ChildItem -Path $Dir -File -ErrorAction SilentlyContinue).Count
}

# ---------------------------------------------------------------------------
# Fixture repo builders
# ---------------------------------------------------------------------------
function Initialize-FixtureGit
{
    param([string]$Dir)
    Push-Location $Dir
    try
    {
        git init -q 2>$null | Out-Null
        git config user.email "test@example.com" 2>$null | Out-Null
        git config user.name "Test" 2>$null | Out-Null
        git add -A 2>$null | Out-Null
        git commit -q -m "fixture" 2>$null | Out-Null
    }
    finally
    {
        Pop-Location
    }
}

# Write-FixtureFile writes Content to Path followed by exactly one trailing
# "`n", regardless of platform newline conventions. Set-Content alone cannot
# produce this precisely (its own -NoNewline still appends the host EOL via
# Value handling quirks on some PowerShell builds), so callers rely on this
# helper rather than repeating the Set-Content + Add-Content pairing inline.
function Write-FixtureFile
{
    param([string]$Path, [string]$Content)

    Set-Content -Path $Path -Value $Content -NoNewline
    Add-Content -Path $Path -Value "`n" -NoNewline
}

function New-FixtureRepo
{
    param([string]$Dir, [switch]$WithSkills)

    New-Item -ItemType Directory -Path (Join-Path $Dir "agents") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Dir "claude-agents") -Force | Out-Null

    Write-FixtureFile -Path (Join-Path $Dir "agents/alpha.agent.md") -Content "FIXTURE AGENT ALPHA CONTENT"
    Write-FixtureFile -Path (Join-Path $Dir "agents/beta.agent.md") -Content "FIXTURE AGENT BETA CONTENT"
    Write-FixtureFile -Path (Join-Path $Dir "claude-agents/alpha.md") -Content "FIXTURE CLAUDE ALPHA CONTENT"
    Write-FixtureFile -Path (Join-Path $Dir "claude-agents/beta.md") -Content "FIXTURE CLAUDE BETA CONTENT"

    if ($WithSkills)
    {
        New-Item -ItemType Directory -Path (Join-Path $Dir "skills/demo-skill") -Force | Out-Null
        Write-FixtureFile -Path (Join-Path $Dir "skills/demo-skill/SKILL.md") -Content "FIXTURE SKILL MD"
        Write-FixtureFile -Path (Join-Path $Dir "skills/demo-skill/helper.txt") -Content "FIXTURE HELPER"
    }

    Initialize-FixtureGit -Dir $Dir
}

$fixtureRepo = Join-Path $scratchRoot "fixture-repo"
$fixtureRepoSkills = Join-Path $scratchRoot "fixture-repo-skills"
New-Item -ItemType Directory -Path $fixtureRepo -Force | Out-Null
New-Item -ItemType Directory -Path $fixtureRepoSkills -Force | Out-Null
New-FixtureRepo -Dir $fixtureRepo
New-FixtureRepo -Dir $fixtureRepoSkills -WithSkills

# ---------------------------------------------------------------------------
# Invocation helper
# ---------------------------------------------------------------------------
function Invoke-Install
{
    param(
        [string]$Cwd,
        [string]$HomeDir,
        [string]$CopilotHome = "",
        [string[]]$ExtraArgs = @()
    )

    $prevLocation = Get-Location
    $prevHome = $env:HOME
    $prevUserProfile = $env:USERPROFILE
    $prevCopilotHome = $env:COPILOT_HOME

    $output = ""
    $code = -1
    try
    {
        Set-Location $Cwd
        # Ambiguity: the spec says "resolve $HOME at run time" without
        # pinning which environment variable install.ps1 reads on Windows.
        # We set both HOME and USERPROFILE to the same scratch path so the
        # test is robust to either resolution strategy the implementation
        # may choose. See report for this noted as a spec gap.
        $env:HOME = $HomeDir
        $env:USERPROFILE = $HomeDir
        if ($CopilotHome)
        {
            $env:COPILOT_HOME = $CopilotHome
        }
        else
        {
            Remove-Item Env:\COPILOT_HOME -ErrorAction SilentlyContinue
        }

        $allArgs = @("-NoProfile", "-NonInteractive", "-File", $installPs1) + $ExtraArgs
        $output = & pwsh @allArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    }
    finally
    {
        Set-Location $prevLocation
        if ($null -ne $prevHome) { $env:HOME = $prevHome } else { Remove-Item Env:\HOME -ErrorAction SilentlyContinue }
        if ($null -ne $prevUserProfile) { $env:USERPROFILE = $prevUserProfile } else { Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue }
        if ($null -ne $prevCopilotHome) { $env:COPILOT_HOME = $prevCopilotHome } else { Remove-Item Env:\COPILOT_HOME -ErrorAction SilentlyContinue }
    }

    return @{ Code = $code; Output = $output }
}

# ===========================================================================
# Tier 1 - specification / happy path
# ===========================================================================

function Test-HappyPathCreatesDestinationDirs
{
    $home1 = Join-Path $scratchRoot "t01/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    $result = Invoke-Install -Cwd $fixtureRepo -HomeDir $home1
    if ($result.Code -ne 0) { Write-Note "install exited $($result.Code): $($result.Output)"; return $false }
    if (-not (Test-Path (Join-Path $home1 ".copilot/agents") -PathType Container)) { Write-Note "missing .copilot/agents"; return $false }
    if (-not (Test-Path (Join-Path $home1 ".claude/agents") -PathType Container)) { Write-Note "missing .claude/agents"; return $false }
    return $true
}

function Test-AgentsCopiedToCopilotWithExactContent
{
    $home1 = Join-Path $scratchRoot "t02/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 | Out-Null
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/alpha.agent.md") (Join-Path $fixtureRepo "agents/alpha.agent.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/beta.agent.md") (Join-Path $fixtureRepo "agents/beta.agent.md"))) { return $false }
    return $true
}

function Test-ClaudeAgentsCopiedToClaudeWithExactContent
{
    $home1 = Join-Path $scratchRoot "t03/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 | Out-Null
    if (-not (Assert-FilesEqual (Join-Path $home1 ".claude/agents/alpha.md") (Join-Path $fixtureRepo "claude-agents/alpha.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".claude/agents/beta.md") (Join-Path $fixtureRepo "claude-agents/beta.md"))) { return $false }
    return $true
}

function Test-DestinationFileCountsMatchSourceExactly
{
    $home1 = Join-Path $scratchRoot "t04/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 | Out-Null
    $copilotCount = Count-Files (Join-Path $home1 ".copilot/agents")
    $claudeCount = Count-Files (Join-Path $home1 ".claude/agents")
    if ($copilotCount -ne 2) { Write-Note "expected 2 files in .copilot/agents, got $copilotCount"; return $false }
    if ($claudeCount -ne 2) { Write-Note "expected 2 files in .claude/agents, got $claudeCount"; return $false }
    return $true
}

function Test-ExitCodeZeroOnSuccess
{
    $home1 = Join-Path $scratchRoot "t05/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    $result = Invoke-Install -Cwd $fixtureRepo -HomeDir $home1
    if ($result.Code -ne 0) { Write-Note "expected exit code 0, got $($result.Code)"; return $false }
    return $true
}

function Test-CopilotHomeOverrideRedirectsDestination
{
    $home1 = Join-Path $scratchRoot "t06/home"
    $copilotHome = Join-Path $scratchRoot "t06/custom-copilot"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-Item -ItemType Directory -Path $copilotHome -Force | Out-Null
    Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 -CopilotHome $copilotHome | Out-Null
    if (-not (Assert-FileExists (Join-Path $copilotHome "agents/alpha.agent.md"))) { return $false }
    if (-not (Assert-FileExists (Join-Path $copilotHome "agents/beta.agent.md"))) { return $false }
    if (-not (Assert-DirAbsent (Join-Path $home1 ".copilot"))) { return $false }
    return $true
}

function Test-MissingSkillsDirSkippedSilently
{
    $home1 = Join-Path $scratchRoot "t07/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    $result = Invoke-Install -Cwd $fixtureRepo -HomeDir $home1
    if ($result.Code -ne 0) { Write-Note "expected exit 0 when skills/ absent, got $($result.Code)"; return $false }
    if (-not (Assert-DirAbsent (Join-Path $home1 ".claude/skills"))) { return $false }
    if (-not (Assert-DirAbsent (Join-Path $home1 ".copilot/skills"))) { return $false }
    return $true
}

function Test-SkillsDirCopiedToBothTargetsWhenPresent
{
    $home1 = Join-Path $scratchRoot "t08/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    Invoke-Install -Cwd $fixtureRepoSkills -HomeDir $home1 | Out-Null
    if (-not (Assert-FilesEqual (Join-Path $home1 ".claude/skills/demo-skill/SKILL.md") (Join-Path $fixtureRepoSkills "skills/demo-skill/SKILL.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".claude/skills/demo-skill/helper.txt") (Join-Path $fixtureRepoSkills "skills/demo-skill/helper.txt"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/skills/demo-skill/SKILL.md") (Join-Path $fixtureRepoSkills "skills/demo-skill/SKILL.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/skills/demo-skill/helper.txt") (Join-Path $fixtureRepoSkills "skills/demo-skill/helper.txt"))) { return $false }
    return $true
}

function Test-NestedDestinationDirsCreatedFromEmptyHome
{
    $home1 = Join-Path $scratchRoot "t09/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    if (@(Get-ChildItem -Path $home1 -Force -ErrorAction SilentlyContinue).Count -ne 0) { Write-Note "precondition failed: home not empty"; return $false }
    Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 | Out-Null
    if (-not (Assert-FileExists (Join-Path $home1 ".claude/agents/alpha.md"))) { return $false }
    if (-not (Assert-FileExists (Join-Path $home1 ".copilot/agents/alpha.agent.md"))) { return $false }
    return $true
}

# ===========================================================================
# Tier 2 - adversarial / boundary
# ===========================================================================

function Test-NoForceSkipsExistingFileWithoutOverwrite
{
    $home1 = Join-Path $scratchRoot "t10/home"
    New-Item -ItemType Directory -Path (Join-Path $home1 ".copilot/agents") -Force | Out-Null
    Set-Content -Path (Join-Path $home1 ".copilot/agents/alpha.agent.md") -Value "SENTINEL DO NOT OVERWRITE" -NoNewline
    Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 | Out-Null
    return Assert-FileContent (Join-Path $home1 ".copilot/agents/alpha.agent.md") "SENTINEL DO NOT OVERWRITE"
}

function Test-NoForcePrintsNoticeForSkippedFile
{
    $home1 = Join-Path $scratchRoot "t11/home"
    New-Item -ItemType Directory -Path (Join-Path $home1 ".copilot/agents") -Force | Out-Null
    Set-Content -Path (Join-Path $home1 ".copilot/agents/alpha.agent.md") -Value "SENTINEL DO NOT OVERWRITE" -NoNewline
    $result = Invoke-Install -Cwd $fixtureRepo -HomeDir $home1
    if ($result.Output -notmatch '(?i)skip|exist')
    {
        Write-Note "expected some skip/exists notice in output, got: $($result.Output)"
        return $false
    }
    return $true
}

function Test-ForceOverwritesExistingFile
{
    $home1 = Join-Path $scratchRoot "t12/home"
    New-Item -ItemType Directory -Path (Join-Path $home1 ".copilot/agents") -Force | Out-Null
    Set-Content -Path (Join-Path $home1 ".copilot/agents/alpha.agent.md") -Value "SENTINEL DO NOT OVERWRITE" -NoNewline
    Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 -ExtraArgs @("-Force") | Out-Null
    return Assert-FilesEqual (Join-Path $home1 ".copilot/agents/alpha.agent.md") (Join-Path $fixtureRepo "agents/alpha.agent.md")
}

function Test-PartialPreexistingMixedForceOff
{
    $home1 = Join-Path $scratchRoot "t13/home"
    New-Item -ItemType Directory -Path (Join-Path $home1 ".copilot/agents") -Force | Out-Null
    Set-Content -Path (Join-Path $home1 ".copilot/agents/alpha.agent.md") -Value "SENTINEL ALPHA" -NoNewline
    Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 | Out-Null
    if (-not (Assert-FileContent (Join-Path $home1 ".copilot/agents/alpha.agent.md") "SENTINEL ALPHA")) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/beta.agent.md") (Join-Path $fixtureRepo "agents/beta.agent.md"))) { return $false }
    return $true
}

function Test-IdempotentRerunWithoutForce
{
    $home1 = Join-Path $scratchRoot "t14/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 | Out-Null
    $result = Invoke-Install -Cwd $fixtureRepo -HomeDir $home1
    if ($result.Code -ne 0) { Write-Note "second no-force run exited $($result.Code)"; return $false }
    return Assert-FilesEqual (Join-Path $home1 ".copilot/agents/alpha.agent.md") (Join-Path $fixtureRepo "agents/alpha.agent.md")
}

function Test-IdempotentRerunWithForceX3
{
    $home1 = Join-Path $scratchRoot "t15/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    for ($i = 1; $i -le 3; $i++)
    {
        $result = Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 -ExtraArgs @("-Force")
        if ($result.Code -ne 0) { Write-Note "force run #$i exited $($result.Code)"; return $false }
        if (-not (Assert-FilesEqual (Join-Path $home1 ".claude/agents/alpha.md") (Join-Path $fixtureRepo "claude-agents/alpha.md")))
        {
            Write-Note "mismatch after force run #$i"
            return $false
        }
    }
    return $true
}

function Test-ByteForByteStubKillerAllTargets
{
    $home1 = Join-Path $scratchRoot "t16/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    Invoke-Install -Cwd $fixtureRepoSkills -HomeDir $home1 | Out-Null
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/beta.agent.md") (Join-Path $fixtureRepoSkills "agents/beta.agent.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".claude/agents/beta.md") (Join-Path $fixtureRepoSkills "claude-agents/beta.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".claude/skills/demo-skill/SKILL.md") (Join-Path $fixtureRepoSkills "skills/demo-skill/SKILL.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/skills/demo-skill/SKILL.md") (Join-Path $fixtureRepoSkills "skills/demo-skill/SKILL.md"))) { return $false }
    return $true
}

function Test-RepoRootResolvedFromCwdNotScriptLocation
{
    $home1 = Join-Path $scratchRoot "t17/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    # Invoke from a subdirectory deep inside the fixture repo, NOT its root,
    # and not anywhere near install.ps1's own location. The installer must
    # still resolve the fixture repo as the source root via
    # `git rev-parse --show-toplevel`, not via its own script path.
    $nestedCwd = Join-Path $fixtureRepo "agents"
    $result = Invoke-Install -Cwd $nestedCwd -HomeDir $home1
    if ($result.Code -ne 0) { Write-Note "install exited $($result.Code) when invoked from a nested cwd: $($result.Output)"; return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/alpha.agent.md") (Join-Path $fixtureRepo "agents/alpha.agent.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".claude/agents/alpha.md") (Join-Path $fixtureRepo "claude-agents/alpha.md"))) { return $false }
    return $true
}

function Test-InvocationOutsideAnyGitRepoFailsNonZero
{
    $home1 = Join-Path $scratchRoot "t18/home"
    $noGitCwd = Join-Path $scratchRoot "t18/no-git-here"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-Item -ItemType Directory -Path $noGitCwd -Force | Out-Null
    $result = Invoke-Install -Cwd $noGitCwd -HomeDir $home1
    if ($result.Code -eq 0) { Write-Note "expected non-zero exit when not inside a git repo, got 0"; return $false }
    return $true
}

function Test-NoWritesOutsideDestinationTree
{
    $home1 = Join-Path $scratchRoot "t19/home"
    $copilotHome = Join-Path $scratchRoot "t19/custom-copilot"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-Item -ItemType Directory -Path $copilotHome -Force | Out-Null
    Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 -CopilotHome $copilotHome | Out-Null

    $scope = Join-Path $scratchRoot "t19"
    $allPaths = Get-ChildItem -Path $scope -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    $stray = $allPaths | Where-Object {
        -not $_.StartsWith($home1, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $_.StartsWith($copilotHome, [System.StringComparison]::OrdinalIgnoreCase) -and
        $_ -ne $home1 -and $_ -ne $copilotHome
    }
    if ($stray)
    {
        Write-Note "stray files/dirs found outside destination trees: $($stray -join ', ')"
        return $false
    }
    return $true
}

function Test-SourceRepoUntouchedAfterInstall
{
    $home1 = Join-Path $scratchRoot "t20/home"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 | Out-Null
    Push-Location $fixtureRepo
    try
    {
        $status = git status --porcelain
    }
    finally
    {
        Pop-Location
    }
    if ($status)
    {
        Write-Note "fixture repo is dirty after install: $status"
        return $false
    }
    return $true
}

function Test-DestinationPathWithSpacesIsHandled
{
    $home1 = Join-Path $scratchRoot "t21/home dir with spaces"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    $result = Invoke-Install -Cwd $fixtureRepo -HomeDir $home1
    if ($result.Code -ne 0) { Write-Note "install exited $($result.Code) with a spaced home path: $($result.Output)"; return $false }
    return Assert-FilesEqual (Join-Path $home1 ".copilot/agents/alpha.agent.md") (Join-Path $fixtureRepo "agents/alpha.agent.md")
}

# ===========================================================================
# Run all scenarios
# ===========================================================================

try
{
    Invoke-Case "Test-HappyPathCreatesDestinationDirs" { Test-HappyPathCreatesDestinationDirs }
    Invoke-Case "Test-AgentsCopiedToCopilotWithExactContent" { Test-AgentsCopiedToCopilotWithExactContent }
    Invoke-Case "Test-ClaudeAgentsCopiedToClaudeWithExactContent" { Test-ClaudeAgentsCopiedToClaudeWithExactContent }
    Invoke-Case "Test-DestinationFileCountsMatchSourceExactly" { Test-DestinationFileCountsMatchSourceExactly }
    Invoke-Case "Test-ExitCodeZeroOnSuccess" { Test-ExitCodeZeroOnSuccess }
    Invoke-Case "Test-CopilotHomeOverrideRedirectsDestination" { Test-CopilotHomeOverrideRedirectsDestination }
    Invoke-Case "Test-MissingSkillsDirSkippedSilently" { Test-MissingSkillsDirSkippedSilently }
    Invoke-Case "Test-SkillsDirCopiedToBothTargetsWhenPresent" { Test-SkillsDirCopiedToBothTargetsWhenPresent }
    Invoke-Case "Test-NestedDestinationDirsCreatedFromEmptyHome" { Test-NestedDestinationDirsCreatedFromEmptyHome }

    Invoke-Case "Test-NoForceSkipsExistingFileWithoutOverwrite" { Test-NoForceSkipsExistingFileWithoutOverwrite }
    Invoke-Case "Test-NoForcePrintsNoticeForSkippedFile" { Test-NoForcePrintsNoticeForSkippedFile }
    Invoke-Case "Test-ForceOverwritesExistingFile" { Test-ForceOverwritesExistingFile }
    Invoke-Case "Test-PartialPreexistingMixedForceOff" { Test-PartialPreexistingMixedForceOff }
    Invoke-Case "Test-IdempotentRerunWithoutForce" { Test-IdempotentRerunWithoutForce }
    Invoke-Case "Test-IdempotentRerunWithForceX3" { Test-IdempotentRerunWithForceX3 }
    Invoke-Case "Test-ByteForByteStubKillerAllTargets" { Test-ByteForByteStubKillerAllTargets }
    Invoke-Case "Test-RepoRootResolvedFromCwdNotScriptLocation" { Test-RepoRootResolvedFromCwdNotScriptLocation }
    Invoke-Case "Test-InvocationOutsideAnyGitRepoFailsNonZero" { Test-InvocationOutsideAnyGitRepoFailsNonZero }
    Invoke-Case "Test-NoWritesOutsideDestinationTree" { Test-NoWritesOutsideDestinationTree }
    Invoke-Case "Test-SourceRepoUntouchedAfterInstall" { Test-SourceRepoUntouchedAfterInstall }
    Invoke-Case "Test-DestinationPathWithSpacesIsHandled" { Test-DestinationPathWithSpacesIsHandled }
}
finally
{
    Remove-Scratch
}

# ===========================================================================
# Summary
# ===========================================================================
Write-Host ""
Write-Host "============================================================"
Write-Host "  $script:TestsPassed / $script:TestsRun scenarios passed"
Write-Host "============================================================"

if ($script:Failures.Count -gt 0)
{
    Write-Host "FAILED scenarios:" -ForegroundColor Red
    foreach ($f in $script:Failures)
    {
        Write-Host "  - $f" -ForegroundColor Red
    }
    exit 1
}

exit 0
