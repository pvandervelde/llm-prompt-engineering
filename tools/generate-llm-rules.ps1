# PowerShell script to generate LLM rule files from YAML source in .rules-source directory
# Generates markdown files for Copilot, Cline, and Roo according to the spec

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
        $rules
    )

    $content = "# " + $header + [Environment]::NewLine + [Environment]::NewLine
    foreach ($group in $rules)
    {
        $name = $group.Name
        $groupName = $name.SubString($name.IndexOf("-") + 1)
        $content += "## $($groupName)" + [Environment]::NewLine + [Environment]::NewLine
        foreach ($rule in $group.Group)
        {
            $content += "**$($rule.name):** $($rule.text)" + [Environment]::NewLine
        }
    }

    Set-Content -Path $filePath -Value $content -Encoding UTF8
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
$outputFileCopilot = Join-Path $outputDirCopilot "copilot-instructions.md"
$outputFileCline = Join-Path $outputDirCline ".clinerules"

# Clear existing files in output directories
Remove-Item -Path $outputFileCopilot -ErrorAction SilentlyContinue
Remove-Item -Path $outputFileCline -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $outputDirRooBase "*") -ErrorAction SilentlyContinue

# Read all YAML files in source directory
$yamlFiles = Get-ChildItem -Path $sourceDir -Filter *.yaml

# Aggregate all rules from all files
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
    }

    # $rules is an array of rule objects
    $allRules += $rules
}

#
# Generate Copilot markdown file (single file with all applicable rules)
#
$copilotRules = $allRules | Where-Object { RuleAppliesTo $_ "copilot" } | Group-Object -Property group
Write-Host "Generating Copilot rules file..."
Write-RuleFile `
    -filePath (Join-Path $outputDirCopilot "copilot-instructions.md") `
    -header "Copilot Instructions" `
    -rules $copilotRules

#
# Generate Cline rules file (single file with all applicable rules)
#
$clineRules = $allRules | Where-Object { RuleAppliesTo $_ "cline" } | Group-Object group
Write-Host "Generating Cline rules file..."
Write-RuleFile `
    -filePath (Join-Path $outputDirCline ".clinerules") `
    -header "Cline Instructions" `
    -rules $clineRules

# Generate Roo rules files per mode
# Collect all roo modes from all rules
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
