# Roo Rules Generation Improvement Specification

## Title

Improving Roo Rules Generation with Merge Logic and File Separation

## Problem Description

The current Roo rules generation creates a single file per mode (e.g., `architect.md`) containing all rules for that mode. However, the Copilot generation has more sophisticated logic that:

1. Merges rules marked with `merge_with_others=true` into combined files
2. Keeps language-specific and specialized rules in separate files
3. Uses pattern-based grouping for better organization

The Roo generation should adopt similar logic while maintaining mode-specific filtering.

## Surrounding Context

- Roo code expects mode-specific directories `.roo/rules-<MODE>/` with markdown files
- Current implementation creates one file per mode containing all applicable rules
- Copilot generation successfully uses `merge_with_others` metadata to combine general rules while keeping specialized rules separate
- Rules are organized in `.rules-source/` with numbered prefixes and descriptive names
- Some rules apply to all modes, others are mode-specific

## Proposed Solution

### Design Goals

1. **Merge compatible rules**: Combine rules from files marked with `merge_with_others=true` into a single general file per mode
2. **Preserve specialization**: Keep language/technology-specific rules in separate files per mode
3. **Maintain mode filtering**: Only include rules applicable to each specific Roo mode
4. **Consistent naming**: Use descriptive filenames that match the Copilot pattern
5. **Reduce context size**: Separate language-specific rules to reduce irrelevant context

### Design Constraints

- Must maintain compatibility with existing Roo mode structure
- Must preserve existing mode filtering logic
- Should align with Copilot generation patterns for consistency
- File naming should be intuitive and descriptive

### Design Decisions

- Use existing `merge_with_others` metadata to determine file grouping
- Extract meaningful names from source filenames (e.g., "152-coding-rust" → "rust")
- Create separate files for each technology/language while combining general rules
- Maintain the `rules-{mode}` directory structure

### Alternatives Considered

- **Single file per mode**: Current approach, but creates large files with mixed content
- **All rules separate**: Would create too many small files and lose general rule cohesion
- **Pattern-based grouping**: More complex than needed for Roo's use case

## Design

### Architecture

```mermaid
flowchart TD
    A[.rules-source/ YAML files] --> B[New-RooRules Function]
    B --> C{Has merge_with_others=true?}
    C -->|Yes| D[Combine into general.md]
    C -->|No| E[Create separate {technology}.md]
    D --> F[output/.roo/rules-{mode}/]
    E --> F
    F --> G[Mode-specific rule files]
```

### Data Flow

1. **Rule Collection**: Gather all rules and filter by Roo mode applicability
2. **Categorization**: Separate rules into mergeable vs. individual based on `merge_with_others` metadata
3. **File Generation**:
   - Mergeable rules → Combined into `general.md`
   - Individual rules → Separate `{technology}.md` files
4. **Output**: Write files to `output/.roo/rules-{mode}/` directory

### Module Breakdown

#### Current State Analysis

**Existing Rule Structure:**

- **Mergeable files** (with `merge_with_others=true`):
  - `001-general.yaml` - General coding practices
  - `002-tooling.yaml` - Tool usage guidelines
  - `050-scm.yaml` - Source control management
  - `100-workflow-guidelines.yaml` - Development workflow
- **Separate files** (no merge metadata):
  - `152-coding-rust.yaml` - Rust-specific rules
  - `153-coding-terraform.yaml` - Terraform-specific rules
  - `154-coding-csharp.yaml` - C#-specific rules
  - etc. (language/technology-specific rules)

#### Modified `New-RooRules` Function

```powershell
function New-RooRules {
    param(
        [PSCustomObject[]]$AllRules,
        [hashtable]$OutputPaths
    )

    # Get unique Roo modes
    $rooModes = Get-UniqueRooModes -Rules $AllRules

    foreach ($mode in $rooModes) {
        $modeDir = Join-Path "output/.roo" "rules-$mode"
        New-Item -ItemType Directory -Path $modeDir -Force | Out-Null

        # Filter rules for this mode
        $modeRules = $AllRules | Where-Object { Test-RuleAppliesTo $_ "roo" $mode }

        # Separate mergeable and individual rules
        $mergeableRules = $modeRules | Where-Object { $_.mergeWithOthers -eq $true }
        $individualRules = $modeRules | Where-Object { $_.mergeWithOthers -ne $true }

        # Generate combined file for mergeable rules
        if ($mergeableRules.Count -gt 0) {
            Write-RooModeFile -FilePath (Join-Path $modeDir "$mode.md") -Mode $mode -Rules $mergeableRules -FileType "General"
        }

        # Generate individual files for non-mergeable rules
        $individualGroups = $individualRules | Group-Object sourceFileName
        foreach ($group in $individualGroups) {
            $fileName = Get-RooFileName -SourceFileName $group.Name
            Write-RooModeFile -FilePath (Join-Path $modeDir "$fileName.md") -Mode $mode -Rules $group.Group -FileType $fileName
        }
    }
}
```

#### New Helper Functions

```powershell
function Get-RooFileName {
    param([string]$SourceFileName)

    # Extract meaningful name from source file
    # e.g., "152-coding-rust" → "rust"
    if ($SourceFileName -match "^\d+-coding-(.+)$") {
        return $Matches[1]
    }
    elseif ($SourceFileName -match "^\d+-(.+)$") {
        return $Matches[1]
    }
    else {
        return $SourceFileName
    }
}

function Write-RooModeFile {
    param(
        [string]$FilePath,
        [string]$Mode,
        [PSCustomObject[]]$Rules,
        [string]$FileType
    )

    $content = @()
    $content += "# Roo Instructions - $Mode"
    $content += ""

    if ($FileType -ne "General") {
        $content += "## $FileType"
        $content += ""
    }

    # Group rules by source file for organization within merged files
    $rulesBySource = $Rules | Group-Object sourceFileName

    foreach ($group in $rulesBySource) {
        if ($rulesBySource.Count -gt 1) {
            $groupName = Get-RooFileName -SourceFileName $group.Name
            $content += "## $groupName"
            $content += ""
        }

        foreach ($rule in $group.Group) {
            $content += "**$($rule.name):** $($rule.text)"
        }
        $content += ""
    }

    Set-Content -Path $FilePath -Value ($content -join [Environment]::NewLine) -Encoding UTF8
}
```

### Other Relevant Details

#### Expected Output Structure

**For `architect` mode:**

```
output/.roo/rules-architect/
├── general.md           # Combined: general + tooling + scm + workflow-guidelines
├── rust.md              # Rust-specific rules for architect mode
├── terraform.md         # Terraform-specific rules for architect mode
├── markdown.md          # Markdown-specific rules for architect mode
└── ...
```

**For `code` mode:**

```
output/.roo/rules-code/
├── general.md           # Combined: general + tooling + scm + workflow-guidelines
├── rust.md              # Rust-specific rules for code mode
├── csharp.md            # C#-specific rules for code mode
├── python.md            # Python-specific rules for code mode
└── ...
```

#### File Organization Strategy

1. **Mergeable rules**: Files with `merge_with_others=true` → Combined into `general.md`
2. **Separate rules**: Files without merge metadata → Individual `{technology}.md` files
3. **Mode filtering**: Only include rules where the `roo` editor contains the target mode

## Implementation Plan

1. **Modify `New-RooRules` function** to implement the new merging logic
2. **Add helper functions** `Get-RooFileName` and `Write-RooModeFile`
3. **Update the existing mode collection logic** to use a dedicated function
4. **Test with existing rule files** to ensure proper categorization
5. **Validate output structure** matches the expected format

## Benefits

1. **Reduced context size**: Separate language-specific rules reduce irrelevant context
2. **Better organization**: General rules combined, specialized rules separated
3. **Consistency**: Aligns with Copilot generation patterns
4. **Maintainability**: Clear separation between general and specific rules
5. **Mode-specific filtering**: Each mode gets only applicable rules
6. **Improved usability**: Users can focus on relevant rule sets for their current technology stack

## Conclusion

This specification provides a clear path to improve Roo rules generation by adopting the successful patterns from Copilot generation while maintaining Roo's mode-specific requirements. The approach balances rule organization, context reduction, and maintainability to create a more effective rule management system.
