# PowerShell script to generate LLM rule files from YAML source in .rules-source directory
# Generates markdown files for Copilot, Cline, and Roo according to the spec
# Updated for Copilot .instructions.md grouping logic (2025-05-14)

# Requires powershell-yaml module: Install-Module powershell-yaml

[CmdletBinding()]
param(
    [string]$sourceDir = ".rules-source",
    [string]$outputDirCopilot = "output/.github",
    [string]$outputDirCline = "output/.clinerules",
    [string]$outputDirRooBase = "output/.roo/rules"
)

Import-Module powershell-yaml -ErrorAction Stop

# ------------------------- Functions -------------------------
# Helper function to check if a rule applies to a given editor and mode
function RuleAppliesTo
{
    param(
        $rule,
        $editorName,
        $mode = $null
    )

    # If no editors metadata, applies to all
    if (-not $rule.editors)
    {
        return $true
    }
    foreach ($ed in $rule.editors)
    {
        if ($ed.name -eq $editorName)
        {
            # If no modes specified, applies to all modes
            if (-not $ed.modes)
            {
                return $true
            }

            # If mode is null, check if any mode applies
            if (-not $mode)
            {
                return $true
            }

            # Check if mode is in modes list
            if ($ed.modes -contains $mode)
            {
                return $true
            }
        }
    }
    return $false
}

function Write-RuleFile
{
    param(
        $filePath,
        $header,
        $patterns,
        $rules
    )

    # Initialize content as an array for proper appending
    $content = @()

    # Add YAML frontmatter if patterns exist
    if ($patterns -and $patterns.Count -gt 0)
    {
        $content += "---"
        if ($patterns.Count -eq 1)
        {
            $content += "applyTo: `"$($patterns[0])`""
        }
        else
        {
            $content += "applyTo:"
            foreach ($p in $patterns)
            {
                $content += "  - `"$p`""
            }
        }
        $content += "---"
        $content += ""
    }

    # Add header
    $content += "# $header"
    $content += ""

    # Add rules
    foreach ($group in $rules)
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
    Set-Content -Path $filePath -Value ($content -join [Environment]::NewLine) -Encoding UTF8
}

#--------------------------End of Functions--------------------------

# Ensure output directories exist
if (-not (Test-Path $outputDirCopilot))
{
    New-Item -ItemType Directory -Path $outputDirCopilot | Out-Null
}

if (-not (Test-Path $outputDirCline))
{
    New-Item -ItemType Directory -Path $outputDirCline | Out-Null
}
if (-not (Test-Path $outputDirRooBase))
{
    New-Item -ItemType Directory -Path $outputDirRooBase | Out-Null
}

# Define output files and directories
$outputFileCline = Join-Path $outputDirCline ".clinerules"
$instructionsDir = Join-Path $outputDirCopilot "instructions"

# Clear existing files in output directories
Remove-Item -Path $outputFileCline -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $outputDirRooBase "*") -ErrorAction SilentlyContinue
if (Test-Path $instructionsDir)
{
    Remove-Item -Path (Join-Path $instructionsDir "*") -ErrorAction SilentlyContinue
}
else
{
    New-Item -ItemType Directory -Path $instructionsDir | Out-Null
}

# Read all YAML files in source directory
$yamlFiles = Get-ChildItem -Path $sourceDir -Filter *.yaml

# Aggregate all rules from all files, and track source file
$allRules = @()

Write-Host "Reading YAML files..."
foreach ($file in $yamlFiles)
{
    $content = Get-Content -Path $file.FullName -Raw
    $rules = ConvertFrom-Yaml $content

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.FullName)
    $ruleGroup = $fileName

    foreach ($rule in $rules)
    {
        $rule.group = $ruleGroup
        $rule.sourceFileName = $fileName
    }

    # $rules is an array of rule objects
    $allRules += $rules
}

#
# Generate Copilot .instructions.md files according to new apply-to grouping logic
#
Write-Host "Generating Copilot .instructions.md files..."
$copilotRules = $allRules | Where-Object { RuleAppliesTo $_ "copilot" }

# Group 1: Rules with no apply-to or apply-to contains "**", grouped by source file
$copilotGroupA = $copilotRules | Where-Object { -not $_.'apply-to' -or $_.'apply-to' -contains '**' } | Group-Object sourceFileName
foreach ($group in $copilotGroupA)
{
    $fileName = $group.Name
    $wrappedGroup = @{ Name = $fileName; Group = $group.Group }
    Write-RuleFile `
        -filePath (Join-Path $instructionsDir "$fileName.instructions.md") `
        -header "Copilot Instructions" `
        -patterns @( "**" ) `
        -rules @($wrappedGroup)
}

# Group 2: Rules with apply-to (excluding "**"), grouped by identical sorted apply-to sets
$copilotGroupB = $copilotRules | Where-Object { $_.'apply-to' -and ($_.'apply-to' | Where-Object { $_ -ne '**' }) } | Group-Object sourceFileName
foreach ($group in $copilotGroupB)
{
    $fileName = $group.Name
    $patterns = $group.Group[0].'apply-to' | Where-Object { $_ -ne '**' } | Sort-Object
    $filePath = Join-Path $instructionsDir "$fileName.instructions.md"

    $wrappedGroup = @{ Name = $fileName; Group = $group.Group }
    Write-RuleFile `
        -filePath (Join-Path $instructionsDir "$fileName.instructions.md") `
        -header "Copilot Instructions" `
        -patterns $patterns `
        -rules @($wrappedGroup)
}

#
# Generate Cline rules file (single file with all applicable rules)
#
$clineRules = $allRules | Where-Object { RuleAppliesTo $_ "cline" } | Group-Object group
Write-Host "Generating Cline rules file..."
Write-RuleFile `
    -filePath (Join-Path $outputDirCline ".clinerules") `
    -header "Cline Instructions" `
    -rules $clineRules

# Generate Roo rules files per mode (unchanged)
Write-Host "Generating Roo rules files..."
$rooModes = @()
foreach ($rule in $allRules)
{
    if ($rule.editors)
    {
        foreach ($ed in $rule.editors)
        {
            if ($ed.name -eq "roo" -and $ed.modes)
            {
                $rooModes += $ed.modes
            }
        }
    }
}
$rooModes = $rooModes | Select-Object -Unique

# For each mode, create a directory and write rules applicable to that mode
foreach ($mode in $rooModes)
{
    $modeDir = Join-Path "output/.roo" "rules-$mode"
    if (-not (Test-Path $modeDir))
    {
        New-Item -ItemType Directory -Path $modeDir | Out-Null
    }

    $modeRules = $allRules | Where-Object { RuleAppliesTo $_ "roo" $mode } | Group-Object -Property group
    Write-RuleFile `
        -filePath (Join-Path $modeDir "$mode.md") `
        -header "Roo Instructions - $mode" `
        -rules $modeRules
}

Write-Output "LLM rule files generated successfully."
