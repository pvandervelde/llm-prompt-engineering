#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Global installer for agent/skill distribution (~/.claude, ~/.copilot)
.DESCRIPTION
    Copies agents/*.agent.md -> ~/.copilot/agents/, claude-agents/*.md ->
    ~/.claude/agents/, and (if present) skills/<name>/ -> both
    ~/.claude/skills/<name>/ and ~/.copilot/skills/<name>/, unchanged.
.PARAMETER Force
    Overwrite existing destination files.
.EXAMPLE
    .\install.ps1
    .\install.ps1 -Force
#>

param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve the repo root via git, from the current working directory. This
# script may be installed globally (e.g. a user's ~/.claude or ~/.copilot
# tools directory) and invoked against any repo as the current working
# directory, so the repo root must come from git, never from where this
# script itself happens to live (see issue #34).
$root = $null
try
{
    $root = (& git rev-parse --show-toplevel 2>$null)
}
catch
{
    $root = $null
}

function Write-Success
{
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Notice
{
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Err
{
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

if (-not $root)
{
    Write-Err "Not in a git repository. Run this from inside a git repository."
    exit 1
}

# $HOME is PowerShell 7+'s built-in automatic variable; it already
# normalizes to $env:USERPROFILE on Windows and $env:HOME on Unix, so we
# deliberately do not branch on OS to pick between environment variables.
if (-not $HOME)
{
    Write-Err "Unable to resolve `$HOME."
    exit 1
}

$copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME ".copilot" }
$claudeHome = Join-Path $HOME ".claude"

$script:Failed = $false

# Test-IsReparsePoint is the security chokepoint shared by every place a
# source entry (file or directory) is about to be read or enumerated: never
# follow a symlink/junction out of the source tree. A reparse point planted
# inside agents/, claude-agents/, or skills/ (valid or dangling, pointing at
# a file OR a directory) could otherwise be used to read and exfiltrate
# arbitrary content the invoking user can access into ~/.claude/skills/,
# which a future AI agent session would read back as trusted content.
# Reject every symlinked/junction source entry explicitly rather than
# dereferencing it, regardless of whether its target exists. Hard links are
# not reparse points and are not rejected here (same posture as `[ -L ]` in
# install.sh, which does not catch hard links either). Returns $true (and
# prints the standard rejection notice, sets $script:Failed) when Path is a
# reparse point; returns $false otherwise.
function Test-IsReparsePoint
{
    param([string]$Path)

    $item = Get-Item -Path $Path -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint))
    {
        Write-Err "Refusing to follow symlink (security): $Path"
        $script:Failed = $true
        return $true
    }
    return $false
}

# Copy-OneFile copies a single file, honoring -Force skip/overwrite
# semantics and creating destination directories as needed.
function Copy-OneFile
{
    param([string]$Src, [string]$Dst)

    if (Test-IsReparsePoint -Path $Src)
    {
        return
    }

    $dstDir = Split-Path -Parent $Dst
    try
    {
        if (-not (Test-Path $dstDir -PathType Container))
        {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
    }
    catch
    {
        Write-Err "Failed to create directory: $dstDir ($_)"
        $script:Failed = $true
        return
    }

    if ((Test-Path $Dst -PathType Leaf) -and -not $Force)
    {
        Write-Notice "Skipping existing file (use -Force to overwrite): $Dst"
        return
    }

    try
    {
        Copy-Item -Path $Src -Destination $Dst -Force
        Write-Success "Copied $(Split-Path -Leaf $Src) -> $Dst"
    }
    catch
    {
        Write-Err "Failed to copy $Src -> $Dst ($_)"
        $script:Failed = $true
    }
}

# Copy-GlobFiles copies every file directly under SrcDir matching Filter
# (non-recursive) into DstDir via Copy-OneFile. Does nothing if SrcDir does
# not exist.
function Copy-GlobFiles
{
    param([string]$SrcDir, [string]$Filter, [string]$DstDir)

    # Security: reject a symlinked/junction source directory before ever
    # enumerating into it - see Test-IsReparsePoint. Without this,
    # Test-Path -PathType Container below follows the reparse point and
    # Get-ChildItem happily lists through it, and every resulting file path
    # is a *regular* path (not itself a reparse point), so Copy-OneFile's
    # own check never trips.
    if (Test-IsReparsePoint -Path $SrcDir)
    {
        return
    }

    if (-not (Test-Path $SrcDir -PathType Container))
    {
        return
    }

    $enumErrors = $null
    $files = Get-ChildItem -Path $SrcDir -Filter $Filter -File -ErrorAction SilentlyContinue -ErrorVariable enumErrors
    if ($enumErrors)
    {
        foreach ($e in $enumErrors)
        {
            Write-Err "Failed to fully enumerate $SrcDir ($e)"
        }
        $script:Failed = $true
    }
    foreach ($f in $files)
    {
        Copy-OneFile -Src $f.FullName -Dst (Join-Path $DstDir $f.Name)
    }
}

# Copy-Tree recursively copies every file under SrcDir into DstDir,
# preserving the relative directory structure, applying the same -Force
# semantics to each file via Copy-OneFile.
function Copy-Tree
{
    param([string]$SrcDir, [string]$DstDir)

    # Security: reject a symlinked/junction source directory before ever
    # walking it - see Test-IsReparsePoint. Without this, Get-ChildItem
    # -Recurse below would follow the reparse point and enumerate every
    # file underneath it as a *regular* path, so Copy-OneFile's own check
    # never trips.
    if (Test-IsReparsePoint -Path $SrcDir)
    {
        return
    }

    $enumErrors = $null
    $files = Get-ChildItem -Path $SrcDir -Recurse -File -ErrorAction SilentlyContinue -ErrorVariable enumErrors
    if ($enumErrors)
    {
        foreach ($e in $enumErrors)
        {
            Write-Err "Failed to fully enumerate $SrcDir ($e)"
        }
        $script:Failed = $true
    }
    foreach ($file in $files)
    {
        $rel = $file.FullName.Substring($SrcDir.Length).TrimStart('\', '/')
        $dstPath = Join-Path $DstDir $rel
        Copy-OneFile -Src $file.FullName -Dst $dstPath
    }
}

Write-Host "Installing agents and skills..."

# ----------------------------------------------------------------------------
# Copilot agents: agents/*.agent.md -> $copilotHome/agents/
# ----------------------------------------------------------------------------
Copy-GlobFiles -SrcDir (Join-Path $root "agents") -Filter "*.agent.md" -DstDir (Join-Path $copilotHome "agents")

# ----------------------------------------------------------------------------
# Claude agents: claude-agents/*.md -> $claudeHome/agents/
# ----------------------------------------------------------------------------
Copy-GlobFiles -SrcDir (Join-Path $root "claude-agents") -Filter "*.md" -DstDir (Join-Path $claudeHome "agents")

# ----------------------------------------------------------------------------
# Skills: skills/<name>/ -> both $claudeHome/skills/<name>/ and
# $copilotHome/skills/<name>/, unchanged. Skipped silently if skills/ does
# not exist in the repo.
# ----------------------------------------------------------------------------
$skillsDir = Join-Path $root "skills"
# Security: reject skills/ itself if it is a symlink/junction before ever
# enumerating into it - see Test-IsReparsePoint. Without this, Test-Path
# -PathType Container below follows the reparse point and lists through it.
if (Test-IsReparsePoint -Path $skillsDir)
{
    # Rejected: skills/ itself is a reparse point - do not enumerate into it.
}
elseif (Test-Path $skillsDir -PathType Container)
{
    $skillDirs = Get-ChildItem -Path $skillsDir -Directory -ErrorAction SilentlyContinue
    foreach ($skill in $skillDirs)
    {
        # Security: reject an individual skills/<name>/ entry that is itself
        # a symlink/junction, even when skills/ is a real directory.
        if (Test-IsReparsePoint -Path $skill.FullName)
        {
            continue
        }
        $claudeSkillsRoot = Join-Path $claudeHome "skills"
        $copilotSkillsRoot = Join-Path $copilotHome "skills"
        Copy-Tree -SrcDir $skill.FullName -DstDir (Join-Path $claudeSkillsRoot $skill.Name)
        Copy-Tree -SrcDir $skill.FullName -DstDir (Join-Path $copilotSkillsRoot $skill.Name)
    }
}

if ($script:Failed)
{
    Write-Err "Install completed with errors."
    exit 1
}

Write-Success "Install complete."
exit 0
