# PowerShell script to generate LLM rule files from YAML source in .rules-source directory
# Generates markdown files for Copilot, Cline, and Roo according to the spec
# Updated for Copilot .instructions.md grouping logic and scope separation (2025-06-30)
#
# This script reads YAML rule files and generates:
# - Copilot instructions separated by scope (user vs repository)
#   * User scope: ./output/copilot/vscode-profile/ (personal preferences)
#   * Repository scope: ./output/copilot/.github/instructions/ (project-specific)
# - Cline rules (single file): ./output/.clinerules/
# - Roo rules (per mode): ./output/.roo/rules-{mode}/
#
# YAML Structure:
# - name: rule-name           # Unique identifier
#   scope: user|repository    # Optional, defaults to 'user'
#   editors:                  # Which editors this rule applies to
#     - name: copilot|cline|roo
#       modes: [ask, edit, agent] # Editor-specific modes
#   apply-to:                 # File patterns (optional)
#     - "**"                  # Global or specific patterns
#   text: |                   # Rule content
#     Rule description here
#
# Requires powershell-yaml module: Install-Module powershell-yaml

[CmdletBinding()]
param(
    [string]$sourceDir = ".rules-source",
    [string]$outputDirCopilot = "output/.github",
    [string]$outputDirCopilotRepo = "output/copilot/.github/instructions",
    [string]$outputDirCopilotUser = "output/copilot/vscode-profile",
    [string]$outputDirCline = "output/.clinerules",
    [string]$outputDirRooBase = "output/.roo/rules"
)

Import-Module powershell-yaml -ErrorAction Stop

# ------------------------- Helper Functions (Alphabetical Order) -------------------------

# Clears existing files in output directories
function Clear-OutputDirectories
{
    param(
        [hashtable]$OutputPaths
    )

    Write-Host "Clearing existing output files..."

    # Clear specific files and directories
    Remove-Item -Path (Join-Path $OutputPaths.Cline ".clinerules") -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $OutputPaths.RooBase "*") -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $OutputPaths.CopilotRepo "*") -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $OutputPaths.CopilotUser "*") -ErrorAction SilentlyContinue

    # Handle legacy instructions directory
    $instructionsDir = Join-Path $OutputPaths.Copilot "instructions"
    if (Test-Path $instructionsDir)
    {
        Remove-Item -Path (Join-Path $instructionsDir "*") -ErrorAction SilentlyContinue
    }
    else
    {
        New-Item -ItemType Directory -Path $instructionsDir | Out-Null
    }
}

# Creates all necessary output directories
function Initialize-OutputDirectories
{
    param(
        [hashtable]$OutputPaths
    )

    Write-Host "Creating output directories..."

    foreach ($pathKey in $OutputPaths.Keys)
    {
        $path = $OutputPaths[$pathKey]
        if (-not (Test-Path $path))
        {
            New-Item -ItemType Directory -Path $path | Out-Null
            Write-Verbose "Created directory: $path"
        }
    }
}

# Generates Cline rules file (single file with all applicable rules)
function New-ClineRules
{
    param(
        [PSCustomObject[]]$AllRules,
        [hashtable]$OutputPaths
    )

    Write-Host "Generating Cline rules file..."

    $clineRules = $AllRules | Where-Object { Test-RuleAppliesTo $_ "cline" } | Group-Object group
    Write-Host "  Found $($clineRules.Count) rule groups for Cline"

    Write-RuleFile `
        -FilePath (Join-Path $OutputPaths.Cline ".clinerules") `
        -Header "Cline Instructions" `
        -Rules $clineRules
}

# Generates Copilot instruction files with scope separation
function New-CopilotInstructions
{
    param(
        [PSCustomObject[]]$AllRules,
        [hashtable]$OutputPaths
    )

    Write-Host "Generating Copilot .instructions.md files..."

    # Filter rules that apply to Copilot
    $copilotRules = $AllRules | Where-Object { Test-RuleAppliesTo $_ "copilot" }

    # Separate rules by scope
    $copilotUserRules = $copilotRules | Where-Object { $_.scope -eq "user" }
    $copilotRepoRules = $copilotRules | Where-Object { $_.scope -eq "repository" }

    Write-Host "  User rules: $($copilotUserRules.Count), Repository rules: $($copilotRepoRules.Count)"

    # Generate User-specific Copilot files
    New-CopilotInstructionsByScope -Rules $copilotUserRules -OutputDir $OutputPaths.CopilotUser -ScopeLabel "User"

    # Generate Repository-specific Copilot files
    New-CopilotInstructionsByScope -Rules $copilotRepoRules -OutputDir $OutputPaths.CopilotRepo -ScopeLabel "Repository"

    # Backward compatibility: Generate legacy format if no scope separation is used
    if ($copilotUserRules.Count -eq 0 -and $copilotRepoRules.Count -eq 0)
    {
        Write-Host "  No scope separation detected, generating legacy format..."
        New-CopilotInstructionsLegacy -Rules $copilotRules -OutputDir (Join-Path $OutputPaths.Copilot "instructions")
    }
}

# Generates Copilot instructions for a specific scope (user or repository)
function New-CopilotInstructionsByScope
{
    param(
        [PSCustomObject[]]$Rules,
        [string]$OutputDir,
        [string]$ScopeLabel
    )

    if ($Rules.Count -eq 0)
    {
        Write-Host "  No $ScopeLabel-scoped rules found"
        return
    }

    Write-Host "  Generating $ScopeLabel-specific Copilot .instructions.md files..."

    # Group 1: Rules with no apply-to or apply-to contains "**", grouped by source file
    $globalRules = $Rules | Where-Object { -not $_.'apply-to' -or $_.'apply-to' -contains '**' } | Group-Object sourceFileName
    foreach ($group in $globalRules)
    {
        $fileName = $group.Name
        $wrappedGroup = @{ Name = $fileName; Group = $group.Group }
        Write-RuleFile `
            -FilePath (Join-Path $OutputDir "$fileName.instructions.md") `
            -Header "Copilot Instructions ($ScopeLabel)" `
            -Patterns @( "**" ) `
            -Rules @($wrappedGroup)
    }

    # Group 2: Rules with specific apply-to patterns (excluding "**"), grouped by source file
    $specificRules = $Rules | Where-Object { $_.'apply-to' -and ($_.'apply-to' | Where-Object { $_ -ne '**' }) } | Group-Object sourceFileName
    foreach ($group in $specificRules)
    {
        $fileName = $group.Name
        $patterns = $group.Group[0].'apply-to' | Where-Object { $_ -ne '**' } | Sort-Object

        $wrappedGroup = @{ Name = $fileName; Group = $group.Group }
        Write-RuleFile `
            -FilePath (Join-Path $OutputDir "$fileName.instructions.md") `
            -Header "Copilot Instructions ($ScopeLabel)" `
            -Patterns $patterns `
            -Rules @($wrappedGroup)
    }
}

# Generates legacy Copilot instructions (for backward compatibility)
function New-CopilotInstructionsLegacy
{
    param(
        [PSCustomObject[]]$Rules,
        [string]$OutputDir
    )

    # Group 1: Rules with no apply-to or apply-to contains "**", grouped by source file
    $globalRules = $Rules | Where-Object { -not $_.'apply-to' -or $_.'apply-to' -contains '**' } | Group-Object sourceFileName
    foreach ($group in $globalRules)
    {
        $fileName = $group.Name
        $wrappedGroup = @{ Name = $fileName; Group = $group.Group }
        Write-RuleFile `
            -FilePath (Join-Path $OutputDir "$fileName.instructions.md") `
            -Header "Copilot Instructions" `
            -Patterns @( "**" ) `
            -Rules @($wrappedGroup)
    }

    # Group 2: Rules with specific apply-to patterns (excluding "**"), grouped by source file
    $specificRules = $Rules | Where-Object { $_.'apply-to' -and ($_.'apply-to' | Where-Object { $_ -ne '**' }) } | Group-Object sourceFileName
    foreach ($group in $specificRules)
    {
        $fileName = $group.Name
        $patterns = $group.Group[0].'apply-to' | Where-Object { $_ -ne '**' } | Sort-Object

        $wrappedGroup = @{ Name = $fileName; Group = $group.Group }
        Write-RuleFile `
            -FilePath (Join-Path $OutputDir "$fileName.instructions.md") `
            -Header "Copilot Instructions" `
            -Patterns $patterns `
            -Rules @($wrappedGroup)
    }
}

# Generates Roo rules files per mode
function New-RooRules
{
    param(
        [PSCustomObject[]]$AllRules,
        [hashtable]$OutputPaths
    )

    Write-Host "Generating Roo rules files..."

    # Collect all unique Roo modes
    $rooModes = @()
    foreach ($rule in $AllRules)
    {
        if ($rule.editors)
        {
            foreach ($editor in $rule.editors)
            {
                if ($editor.name -eq "roo" -and $editor.modes)
                {
                    $rooModes += $editor.modes
                }
            }
        }
    }
    $rooModes = $rooModes | Select-Object -Unique
    Write-Host "  Found Roo modes: $($rooModes -join ', ')"

    # Generate rules file for each mode
    foreach ($mode in $rooModes)
    {
        $modeDir = Join-Path "output/.roo" "rules-$mode"
        if (-not (Test-Path $modeDir))
        {
            New-Item -ItemType Directory -Path $modeDir | Out-Null
        }

        $modeRules = $AllRules | Where-Object { Test-RuleAppliesTo $_ "roo" $mode } | Group-Object -Property group
        Write-Host "  Mode '$mode': $($modeRules.Count) rule groups"

        Write-RuleFile `
            -FilePath (Join-Path $modeDir "$mode.md") `
            -Header "Roo Instructions - $mode" `
            -Rules $modeRules
    }
}

# Loads and processes all YAML rule files
function Read-YamlRules
{
    param(
        [string]$SourceDirectory
    )

    Write-Host "Reading YAML files from $SourceDirectory..."

    $yamlFiles = Get-ChildItem -Path $SourceDirectory -Filter *.yaml
    $allRules = @()

    foreach ($file in $yamlFiles)
    {
        Write-Verbose "Processing file: $($file.Name)"

        $content = Get-Content -Path $file.FullName -Raw
        $rules = ConvertFrom-Yaml $content

        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.FullName)
        $ruleGroup = $fileName

        foreach ($rule in $rules)
        {
            # Enrich each rule with metadata
            $rule.group = $ruleGroup
            $rule.sourceFileName = $fileName

            # Set default scope to 'user' if not specified (backward compatibility)
            if (-not $rule.scope)
            {
                $rule.scope = "user"
            }
        }

        $allRules += $rules
        Write-Verbose "Loaded $($rules.Count) rules from $($file.Name)"
    }

    Write-Host "Loaded $($allRules.Count) rules from $($yamlFiles.Count) files"
    return $allRules
}

# Helper function to check if a rule applies to a given editor and mode
function Test-RuleAppliesTo
{
    param(
        [PSCustomObject]$Rule,
        [string]$EditorName,
        [string]$Mode = $null
    )

    # If no editors metadata, applies to all
    if (-not $Rule.editors)
    {
        return $true
    }

    foreach ($editor in $Rule.editors)
    {
        if ($editor.name -eq $EditorName)
        {
            # If no modes specified, applies to all modes
            if (-not $editor.modes)
            {
                return $true
            }

            # If mode is null, check if any mode applies
            if (-not $Mode)
            {
                return $true
            }

            # Check if mode is in modes list
            if ($editor.modes -contains $Mode)
            {
                return $true
            }
        }
    }
    return $false
}

# Writes a rule file with YAML frontmatter and grouped rules
function Write-RuleFile
{
    param(
        [string]$FilePath,
        [string]$Header,
        [string[]]$Patterns,
        [PSCustomObject[]]$Rules
    )

    # Initialize content as an array for proper appending
    $content = @()

    # Add YAML frontmatter if patterns exist
    if ($Patterns -and $Patterns.Count -gt 0)
    {
        $content += "---"
        if ($Patterns.Count -eq 1)
        {
            $content += "applyTo: `"$($Patterns[0])`""
        }
        else
        {
            $content += "applyTo:"
            foreach ($pattern in $Patterns)
            {
                $content += "  - `"$pattern`""
            }
        }
        $content += "---"
        $content += ""
    }

    # Add header
    $content += "# $Header"
    $content += ""

    # Add rules grouped by source file
    foreach ($group in $Rules)
    {
        $name = $group.Name
        $groupName = $name.SubString($name.IndexOf("-") + 1)
        $content += "## $($groupName)"
        $content += ""
        foreach ($rule in $group.Group)
        {
            $content += "**$($rule.name):** $($rule.text)"
        }
        $content += ""
    }

    # Write all content joined by newlines
    Set-Content -Path $FilePath -Value ($content -join [Environment]::NewLine) -Encoding UTF8
}

#--------------------------End of Functions--------------------------

# ------------------------- Main Script Execution -------------------------

# Validate prerequisites
try
{
    Import-Module powershell-yaml -ErrorAction Stop
}
catch
{
    Write-Error "Required module 'powershell-yaml' not found. Install with: Install-Module powershell-yaml"
    exit 1
}

# Define all output paths for easy management
$outputPaths = @{
    Copilot     = $outputDirCopilot
    CopilotRepo = $outputDirCopilotRepo
    CopilotUser = $outputDirCopilotUser
    Cline       = $outputDirCline
    RooBase     = $outputDirRooBase
}

Write-Host "=== LLM Rule Generator ==="
Write-Host "Source directory: $sourceDir"
Write-Host "Output directories:"
foreach ($key in $outputPaths.Keys | Sort-Object)
{
    Write-Host "  $key`: $($outputPaths[$key])"
}
Write-Host ""

# Initialize environment
Initialize-OutputDirectories -OutputPaths $outputPaths
Clear-OutputDirectories -OutputPaths $outputPaths

# Load and process YAML rules
$allRules = Read-YamlRules -SourceDirectory $sourceDir

# Generate output files for each editor type
New-CopilotInstructions -AllRules $allRules -OutputPaths $outputPaths
New-ClineRules -AllRules $allRules -OutputPaths $outputPaths
New-RooRules -AllRules $allRules -OutputPaths $outputPaths

Write-Host ""
Write-Host "=== Generation Complete ==="
Write-Output "LLM rule files generated successfully."
