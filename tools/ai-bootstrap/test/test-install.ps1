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

      Tier 3 - QA adversarial audit (post-implementation, issue #68 follow-up)
        22 Test-DanglingSymlinkInAgentsFailsLoudly
        23 Test-SymlinkInSkillsTreeRejectedWithoutLeakingContent
        24 Test-DestinationDirIsSymlinkWritesThroughToTarget
        25 Test-CopilotHomeEnvPointingAtFileFailsLoudly
        26 Test-WeirdSourceFilenamesSurviveByteForByte
        27 Test-SourceRepoPathWithSpacesIsHandled
        28 Test-SymlinkEscapingSourceTreeDoesNotLeakExternalContent

      Tier 4 - symlinked source *directories* (Copilot review follow-up,
      issue #68, 2026-10-12): the Tier 3 fix only rejected symlinked
      individual *files*; a symlinked source *directory* (agents/,
      claude-agents/, skills/, or an individual skills/<name>/ entry)
      bypassed that check entirely because Test-Path/Get-ChildItem
      dereference directories before any per-file check ever runs.
        29 Test-AgentsDirItselfIsSymlinkRejectedWithoutLeakingContent
        30 Test-ClaudeAgentsDirItselfIsSymlinkRejectedWithoutLeakingContent
        31 Test-SkillsRootItselfIsSymlinkRejectedWithoutLeakingContent
        32 Test-SkillEntryItselfIsSymlinkRejectedWithoutLeakingContent
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

# Try-NewSymlink attempts to create a real OS-level symbolic link (not a
# plain copy). On Windows this requires either Developer Mode or an
# elevated/admin token (SeCreateSymbolicLinkPrivilege); without it,
# New-Item -ItemType SymbolicLink throws. Returns $true only when a genuine
# symlink was created, so callers can skip symlink-dependent scenarios with
# a clear notice on hosts that cannot exercise this path, rather than
# silently passing against something that isn't actually a symlink.
function Try-NewSymlink
{
    param([string]$Path, [string]$Target)
    try
    {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop | Out-Null
        $item = Get-Item -Path $Path -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.LinkType -eq "SymbolicLink"))
        {
            return $true
        }
        return $false
    }
    catch
    {
        return $false
    }
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
# Tier 3 - QA adversarial audit (post-implementation, issue #68 follow-up)
# ===========================================================================

function Test-DanglingSymlinkInAgentsFailsLoudly
{
    $dir = Join-Path $scratchRoot "t22/repo"
    $home1 = Join-Path $scratchRoot "t22/home"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-FixtureRepo -Dir $dir
    if (-not (Try-NewSymlink -Path (Join-Path $dir "agents/dangling.agent.md") -Target (Join-Path $dir "agents/does-not-exist.agent.md")))
    {
        Write-Note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return $true
    }
    $result = Invoke-Install -Cwd $dir -HomeDir $home1
    if ($result.Code -eq 0) { Write-Note "expected non-zero exit when a source glob match is a dangling symlink, got 0"; return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/alpha.agent.md") (Join-Path $dir "agents/alpha.agent.md"))) { return $false }
    if (Test-Path (Join-Path $home1 ".copilot/agents/dangling.agent.md")) { Write-Note "dangling.agent.md should not exist at destination"; return $false }
    return $true
}

function Test-SymlinkInSkillsTreeRejectedWithoutLeakingContent
{
    # Security regression test: a symlink inside skills/ - even one whose
    # target is a perfectly valid file - must be rejected, not followed.
    # Earlier drafts of this installer dereferenced the symlink and copied
    # its target's content verbatim into both ~/.claude and ~/.copilot,
    # which is exactly the vector a planted symlink could use to exfiltrate
    # an arbitrary file into a tree a future AI agent session reads back as
    # trusted content. See .llm/findings/global-installer-68.md.
    $dir = Join-Path $scratchRoot "t23/repo"
    $home1 = Join-Path $scratchRoot "t23/home"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-FixtureRepo -Dir $dir
    New-Item -ItemType Directory -Path (Join-Path $dir "skills/demo-skill") -Force | Out-Null
    Write-FixtureFile -Path (Join-Path $dir "skills/demo-skill/real.txt") -Content "REAL SKILL FILE"
    if (-not (Try-NewSymlink -Path (Join-Path $dir "skills/demo-skill/linked.txt") -Target (Join-Path $dir "skills/demo-skill/real.txt")))
    {
        Write-Note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return $true
    }
    Initialize-FixtureGit -Dir $dir
    $result = Invoke-Install -Cwd $dir -HomeDir $home1
    if ($result.Code -eq 0) { Write-Note "expected non-zero exit when skills/ contained a symlink, got 0"; return $false }
    if ($result.Output -notmatch '(?i)symlink') { Write-Note "expected a symlink-rejection notice in output, got: $($result.Output)"; return $false }
    if (Test-Path (Join-Path $home1 ".claude/skills/demo-skill/linked.txt")) { Write-Note "linked.txt should not exist at .claude destination"; return $false }
    if (Test-Path (Join-Path $home1 ".copilot/skills/demo-skill/linked.txt")) { Write-Note "linked.txt should not exist at .copilot destination"; return $false }
    # The real, non-symlinked sibling must still be installed correctly -
    # rejecting one symlinked entry must not abort the whole skill copy.
    if (-not (Assert-FileContent (Join-Path $home1 ".claude/skills/demo-skill/real.txt") "REAL SKILL FILE")) { return $false }
    if (-not (Assert-FileContent (Join-Path $home1 ".copilot/skills/demo-skill/real.txt") "REAL SKILL FILE")) { return $false }
    return $true
}

function Test-DestinationDirIsSymlinkWritesThroughToTarget
{
    $home1 = Join-Path $scratchRoot "t24/home"
    $realTarget = Join-Path $scratchRoot "t24/real-copilot-target"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-Item -ItemType Directory -Path $realTarget -Force | Out-Null
    if (-not (Try-NewSymlink -Path (Join-Path $home1 ".copilot") -Target $realTarget))
    {
        Write-Note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return $true
    }
    $result = Invoke-Install -Cwd $fixtureRepo -HomeDir $home1
    if ($result.Code -ne 0) { Write-Note "install exited $($result.Code) when the destination dir was a symlink: $($result.Output)"; return $false }
    if (-not (Assert-FilesEqual (Join-Path $realTarget "agents/alpha.agent.md") (Join-Path $fixtureRepo "agents/alpha.agent.md"))) { return $false }
    $item = Get-Item -Path (Join-Path $home1 ".copilot") -Force
    if ($item.LinkType -ne "SymbolicLink") { Write-Note "expected $home1/.copilot to remain a symlink"; return $false }
    return $true
}

function Test-CopilotHomeEnvPointingAtFileFailsLoudly
{
    $home1 = Join-Path $scratchRoot "t25/home"
    $copilotHomeFile = Join-Path $scratchRoot "t25/copilot-home-as-a-file"
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    Set-Content -Path $copilotHomeFile -Value "NOT A DIRECTORY" -NoNewline
    $result = Invoke-Install -Cwd $fixtureRepo -HomeDir $home1 -CopilotHome $copilotHomeFile
    if ($result.Code -eq 0) { Write-Note "expected non-zero exit when `$env:COPILOT_HOME points at a file, got 0"; return $false }
    return Assert-FileContent $copilotHomeFile "NOT A DIRECTORY"
}

function Test-WeirdSourceFilenamesSurviveByteForByte
{
    $dir = Join-Path $scratchRoot "t26/repo"
    $home1 = Join-Path $scratchRoot "t26/home"
    New-Item -ItemType Directory -Path (Join-Path $dir "agents") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dir "claude-agents") -Force | Out-Null
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    Write-FixtureFile -Path (Join-Path $dir "agents/with space.agent.md") -Content "SPACE NAME"
    Write-FixtureFile -Path (Join-Path $dir "agents/café.agent.md") -Content "UNICODE NAME"
    Write-FixtureFile -Path (Join-Path $dir "agents/-leadingdash.agent.md") -Content "DASH NAME"
    Write-FixtureFile -Path (Join-Path $dir "claude-agents/normal.md") -Content "CLAUDE NORMAL"
    Initialize-FixtureGit -Dir $dir
    $result = Invoke-Install -Cwd $dir -HomeDir $home1
    if ($result.Code -ne 0) { Write-Note "install exited $($result.Code) with space/unicode/leading-dash source filenames: $($result.Output)"; return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/with space.agent.md") (Join-Path $dir "agents/with space.agent.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/café.agent.md") (Join-Path $dir "agents/café.agent.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/-leadingdash.agent.md") (Join-Path $dir "agents/-leadingdash.agent.md"))) { return $false }
    return $true
}

function Test-SourceRepoPathWithSpacesIsHandled
{
    $dir = Join-Path $scratchRoot "t27/repo with spaces in its path"
    $home1 = Join-Path $scratchRoot "t27/home"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-FixtureRepo -Dir $dir
    $result = Invoke-Install -Cwd $dir -HomeDir $home1
    if ($result.Code -ne 0) { Write-Note "install exited $($result.Code) with a spaced source repo path: $($result.Output)"; return $false }
    return Assert-FilesEqual (Join-Path $home1 ".copilot/agents/alpha.agent.md") (Join-Path $dir "agents/alpha.agent.md")
}

function Test-SymlinkEscapingSourceTreeDoesNotLeakExternalContent
{
    # Direct reproduction of the HIGH-severity finding from the security
    # audit: a symlink inside agents/ pointing OUTSIDE the repo entirely
    # (e.g. simulating a path under the user's profile) must never have its
    # content copied into the destination tree.
    $dir = Join-Path $scratchRoot "t28/repo"
    $home1 = Join-Path $scratchRoot "t28/home"
    $secret = Join-Path $scratchRoot "t28/outside-repo-secret.txt"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-FixtureRepo -Dir $dir
    Set-Content -Path $secret -Value "SUPER-SECRET-SSH-KEY-CONTENT-DO-NOT-LEAK" -NoNewline
    if (-not (Try-NewSymlink -Path (Join-Path $dir "agents/evil.agent.md") -Target $secret))
    {
        Write-Note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return $true
    }
    $result = Invoke-Install -Cwd $dir -HomeDir $home1
    if ($result.Code -eq 0) { Write-Note "expected non-zero exit when a source symlink escapes the repo, got 0"; return $false }
    $leaked = Get-ChildItem -Path $home1 -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        (Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue) -match "SUPER-SECRET-SSH-KEY-CONTENT-DO-NOT-LEAK"
    }
    if ($leaked) { Write-Note "SECURITY: external secret content leaked into the destination tree: $($leaked.FullName -join ', ')"; return $false }
    if (Test-Path (Join-Path $home1 ".copilot/agents/evil.agent.md")) { Write-Note "evil.agent.md should not exist at destination"; return $false }
    # Legitimate sibling files must still install correctly.
    return Assert-FilesEqual (Join-Path $home1 ".copilot/agents/alpha.agent.md") (Join-Path $dir "agents/alpha.agent.md")
}

# ===========================================================================
# Tier 4 - symlinked source *directories* (Copilot review follow-up, #68)
# ===========================================================================

function Test-NoSecretLeaked
{
    param([string]$HomeDir, [string]$Secret)
    $leaked = Get-ChildItem -Path $HomeDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        (Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape($Secret)
    }
    if ($leaked)
    {
        Write-Note "SECURITY: external symlink target content leaked into the destination tree: $($leaked.FullName -join ', ')"
        return $false
    }
    return $true
}

function Test-AgentsDirItselfIsSymlinkRejectedWithoutLeakingContent
{
    # The existing per-file symlink check (Copy-OneFile's ReparsePoint
    # check) never even runs here: Test-Path -PathType Container in
    # Copy-GlobFiles dereferences a symlinked agents/ directory, the
    # enumeration proceeds straight through it, and every resulting path is
    # a *regular* file path, not a reparse point.
    $dir = Join-Path $scratchRoot "t29/repo"
    $home1 = Join-Path $scratchRoot "t29/home"
    $external = Join-Path $scratchRoot "t29/external-agents-dir"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-Item -ItemType Directory -Path $external -Force | Out-Null
    Write-FixtureFile -Path (Join-Path $external "leaked.agent.md") -Content "LEAKED-AGENTS-DIR-SECRET"
    New-FixtureRepo -Dir $dir
    Remove-Item -Path (Join-Path $dir "agents") -Recurse -Force
    if (-not (Try-NewSymlink -Path (Join-Path $dir "agents") -Target $external))
    {
        Write-Note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return $true
    }
    $result = Invoke-Install -Cwd $dir -HomeDir $home1
    if ($result.Code -eq 0) { Write-Note "expected non-zero exit when agents/ itself is a symlink, got 0"; return $false }
    if ($result.Output -notmatch '(?i)symlink') { Write-Note "expected a symlink-rejection notice in output, got: $($result.Output)"; return $false }
    if (-not (Test-NoSecretLeaked -HomeDir $home1 -Secret "LEAKED-AGENTS-DIR-SECRET")) { return $false }
    if (-not (Assert-DirAbsent (Join-Path $home1 ".copilot/agents"))) { return $false }
    # Aggregate failure, not early abort: claude-agents/ (a sibling source
    # directory, not itself a symlink) must still install normally.
    if (-not (Assert-FilesEqual (Join-Path $home1 ".claude/agents/alpha.md") (Join-Path $dir "claude-agents/alpha.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".claude/agents/beta.md") (Join-Path $dir "claude-agents/beta.md"))) { return $false }
    return $true
}

function Test-ClaudeAgentsDirItselfIsSymlinkRejectedWithoutLeakingContent
{
    $dir = Join-Path $scratchRoot "t30/repo"
    $home1 = Join-Path $scratchRoot "t30/home"
    $external = Join-Path $scratchRoot "t30/external-claude-agents-dir"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-Item -ItemType Directory -Path $external -Force | Out-Null
    Write-FixtureFile -Path (Join-Path $external "leaked.md") -Content "LEAKED-CLAUDE-AGENTS-DIR-SECRET"
    New-FixtureRepo -Dir $dir
    Remove-Item -Path (Join-Path $dir "claude-agents") -Recurse -Force
    if (-not (Try-NewSymlink -Path (Join-Path $dir "claude-agents") -Target $external))
    {
        Write-Note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return $true
    }
    $result = Invoke-Install -Cwd $dir -HomeDir $home1
    if ($result.Code -eq 0) { Write-Note "expected non-zero exit when claude-agents/ itself is a symlink, got 0"; return $false }
    if ($result.Output -notmatch '(?i)symlink') { Write-Note "expected a symlink-rejection notice in output, got: $($result.Output)"; return $false }
    if (-not (Test-NoSecretLeaked -HomeDir $home1 -Secret "LEAKED-CLAUDE-AGENTS-DIR-SECRET")) { return $false }
    if (-not (Assert-DirAbsent (Join-Path $home1 ".claude/agents"))) { return $false }
    # Aggregate failure, not early abort: agents/ (a sibling source
    # directory, not itself a symlink) must still install normally.
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/alpha.agent.md") (Join-Path $dir "agents/alpha.agent.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/beta.agent.md") (Join-Path $dir "agents/beta.agent.md"))) { return $false }
    return $true
}

function Test-SkillsRootItselfIsSymlinkRejectedWithoutLeakingContent
{
    $dir = Join-Path $scratchRoot "t31/repo"
    $home1 = Join-Path $scratchRoot "t31/home"
    $external = Join-Path $scratchRoot "t31/external-skills-root"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-Item -ItemType Directory -Path $external -Force | Out-Null
    Write-FixtureFile -Path (Join-Path $external "leaked.txt") -Content "LEAKED-SKILLS-ROOT-SECRET"
    New-FixtureRepo -Dir $dir
    if (-not (Try-NewSymlink -Path (Join-Path $dir "skills") -Target $external))
    {
        Write-Note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return $true
    }
    $result = Invoke-Install -Cwd $dir -HomeDir $home1
    if ($result.Code -eq 0) { Write-Note "expected non-zero exit when skills/ itself is a symlink, got 0"; return $false }
    if ($result.Output -notmatch '(?i)symlink') { Write-Note "expected a symlink-rejection notice in output, got: $($result.Output)"; return $false }
    if (-not (Test-NoSecretLeaked -HomeDir $home1 -Secret "LEAKED-SKILLS-ROOT-SECRET")) { return $false }
    if (-not (Assert-DirAbsent (Join-Path $home1 ".claude/skills"))) { return $false }
    if (-not (Assert-DirAbsent (Join-Path $home1 ".copilot/skills"))) { return $false }
    # Aggregate failure, not early abort: agents/ and claude-agents/ must
    # still install normally in the same run.
    if (-not (Assert-FilesEqual (Join-Path $home1 ".copilot/agents/alpha.agent.md") (Join-Path $dir "agents/alpha.agent.md"))) { return $false }
    if (-not (Assert-FilesEqual (Join-Path $home1 ".claude/agents/alpha.md") (Join-Path $dir "claude-agents/alpha.md"))) { return $false }
    return $true
}

function Test-SkillEntryItselfIsSymlinkRejectedWithoutLeakingContent
{
    # skills/ itself is a real directory; one individual entry underneath
    # it (skills/evil-skill) is a symlink to a directory entirely outside
    # the repo. A sibling, non-symlinked skill (skills/demo-skill) must
    # still install correctly in the same run.
    $dir = Join-Path $scratchRoot "t32/repo"
    $home1 = Join-Path $scratchRoot "t32/home"
    $external = Join-Path $scratchRoot "t32/external-evil-skill"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType Directory -Path $home1 -Force | Out-Null
    New-Item -ItemType Directory -Path $external -Force | Out-Null
    Write-FixtureFile -Path (Join-Path $external "leaked.txt") -Content "LEAKED-SKILL-ENTRY-SECRET"
    New-FixtureRepo -Dir $dir
    New-Item -ItemType Directory -Path (Join-Path $dir "skills/demo-skill") -Force | Out-Null
    Write-FixtureFile -Path (Join-Path $dir "skills/demo-skill/real.txt") -Content "REAL SKILL FILE"
    if (-not (Try-NewSymlink -Path (Join-Path $dir "skills/evil-skill") -Target $external))
    {
        Write-Note "SKIPPED: no symlink privilege on this host (Developer Mode / admin required)"
        return $true
    }
    Initialize-FixtureGit -Dir $dir
    $result = Invoke-Install -Cwd $dir -HomeDir $home1
    if ($result.Code -eq 0) { Write-Note "expected non-zero exit when a skills/<name> entry itself is a symlink, got 0"; return $false }
    if ($result.Output -notmatch '(?i)symlink') { Write-Note "expected a symlink-rejection notice in output, got: $($result.Output)"; return $false }
    if (-not (Test-NoSecretLeaked -HomeDir $home1 -Secret "LEAKED-SKILL-ENTRY-SECRET")) { return $false }
    if (-not (Assert-DirAbsent (Join-Path $home1 ".claude/skills/evil-skill"))) { return $false }
    if (-not (Assert-DirAbsent (Join-Path $home1 ".copilot/skills/evil-skill"))) { return $false }
    # Aggregate failure, not early abort: the real sibling skill must still
    # install correctly.
    if (-not (Assert-FileContent (Join-Path $home1 ".claude/skills/demo-skill/real.txt") "REAL SKILL FILE")) { return $false }
    if (-not (Assert-FileContent (Join-Path $home1 ".copilot/skills/demo-skill/real.txt") "REAL SKILL FILE")) { return $false }
    return $true
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

    Invoke-Case "Test-DanglingSymlinkInAgentsFailsLoudly" { Test-DanglingSymlinkInAgentsFailsLoudly }
    Invoke-Case "Test-SymlinkInSkillsTreeRejectedWithoutLeakingContent" { Test-SymlinkInSkillsTreeRejectedWithoutLeakingContent }
    Invoke-Case "Test-DestinationDirIsSymlinkWritesThroughToTarget" { Test-DestinationDirIsSymlinkWritesThroughToTarget }
    Invoke-Case "Test-CopilotHomeEnvPointingAtFileFailsLoudly" { Test-CopilotHomeEnvPointingAtFileFailsLoudly }
    Invoke-Case "Test-WeirdSourceFilenamesSurviveByteForByte" { Test-WeirdSourceFilenamesSurviveByteForByte }
    Invoke-Case "Test-SourceRepoPathWithSpacesIsHandled" { Test-SourceRepoPathWithSpacesIsHandled }
    Invoke-Case "Test-SymlinkEscapingSourceTreeDoesNotLeakExternalContent" { Test-SymlinkEscapingSourceTreeDoesNotLeakExternalContent }

    Invoke-Case "Test-AgentsDirItselfIsSymlinkRejectedWithoutLeakingContent" { Test-AgentsDirItselfIsSymlinkRejectedWithoutLeakingContent }
    Invoke-Case "Test-ClaudeAgentsDirItselfIsSymlinkRejectedWithoutLeakingContent" { Test-ClaudeAgentsDirItselfIsSymlinkRejectedWithoutLeakingContent }
    Invoke-Case "Test-SkillsRootItselfIsSymlinkRejectedWithoutLeakingContent" { Test-SkillsRootItselfIsSymlinkRejectedWithoutLeakingContent }
    Invoke-Case "Test-SkillEntryItselfIsSymlinkRejectedWithoutLeakingContent" { Test-SkillEntryItselfIsSymlinkRejectedWithoutLeakingContent }
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
