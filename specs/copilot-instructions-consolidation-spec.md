# Copilot Instructions Consolidation Specification

## Overview

This specification defines changes to the `generate-llm-rules.ps1` script to consolidate multiple Copilot instruction files into single files per scope, reducing the number of files that Copilot needs to load into its context.

## Current State

### File Structure
The script currently generates multiple `.instructions.md` files for each scope:

- **User scope**: `output/copilot/vscode-profile/`
  - `001-general-user.instructions.md`
  - `002-tooling-user.instructions.md`
  - `050-scm-user.instructions.md`
  - `100-workflow-guidelines-user.instructions.md`
  - `150-coding-user.instructions.md`
  - `152-coding-rust-user.instructions.md`
  - `153-coding-terraform-user.instructions.md`

- **Repository scope**: `output/copilot/.github/instructions/`
  - Similar pattern with `-repository` suffix

### Current Logic
The `New-CopilotInstructionsByScope` function:
1. Groups rules by source file name
2. Creates separate `.instructions.md` files for each source file
3. Handles global rules ("**" patterns) and specific patterns separately
4. Each file contains YAML frontmatter with `applyTo` patterns

## Proposed Changes

### Target File Structure
Instead of one file per source file, organize by pattern matching:

- **User scope**: `output/copilot/vscode-profile/`
  - `user-general.instructions.md` - Rules with global pattern ("**") or no pattern
  - `user-rust.instructions.md` - Rules with pattern `**/*.rs`
  - `user-typescript.instructions.md` - Rules with pattern `**/*.ts`
  - `user-src.instructions.md` - Rules with pattern `src/**`
  - `user-[pattern-name].instructions.md` - Rules with other specific patterns

- **Repository scope**: `output/copilot/.github/instructions/`
  - `general.instructions.md` - Rules with global pattern ("**") or no pattern
  - `rust.instructions.md` - Rules with pattern `**/*.rs`
  - `typescript.instructions.md` - Rules with pattern `**/*.ts`
  - `src.instructions.md` - Rules with pattern `src/**`
  - `[pattern-name].instructions.md` - Rules with other specific patterns

### Benefits
1. **Reduced Context Load**: Fewer files than current source-file approach
2. **Contextual Relevance**: Copilot loads only relevant patterns for current file
3. **Better Organization**: Rules grouped by applicability rather than source origin
4. **Maintained Functionality**: All rules still applied with proper patterns
5. **Logical Grouping**: Related rules naturally grouped together

## Implementation Details

### 1. Modify `New-CopilotInstructionsByScope` Function

**Current Behavior:**
```powershell
# Creates one file per source file group
foreach ($group in $globalRules) {
    $fileName = $group.Name
    Write-RuleFile -FilePath (Join-Path $OutputDir "$fileName$scopeSuffix.instructions.md") ...
}
```

**New Behavior:**
```powershell
# Group rules by pattern and create one file per pattern
$patternGroups = Get-RulesByPattern -Rules $Rules
foreach ($patternGroup in $patternGroups) {
    $fileName = Get-PatternFileName -Pattern $patternGroup.Pattern -ScopeLabel $ScopeLabel
    Write-RuleFile -FilePath (Join-Path $OutputDir "$fileName.instructions.md") ...
}
```

### 2. Pattern-Based File Naming

**Pattern to Filename Mapping:**

**User Scope (prefixed with 'user-'):**
- `"**"` or no pattern → `user-general.instructions.md`
- `"**/*.rs"` → `user-rust.instructions.md`
- `"**/*.ts"` → `user-typescript.instructions.md`
- `"**/*.js"` → `user-javascript.instructions.md`
- `"**/*.py"` → `user-python.instructions.md`
- `"**/*.tf"` → `user-terraform.instructions.md`
- `"src/**"` → `user-src.instructions.md`
- `"test/**"` → `user-test.instructions.md`
- `"docs/**"` → `user-docs.instructions.md`
- Other patterns → `user-[sanitized-pattern-name].instructions.md`

**Repository Scope (no suffix):**
- `"**"` or no pattern → `general.instructions.md`
- `"**/*.rs"` → `rust.instructions.md`
- `"**/*.ts"` → `typescript.instructions.md`
- `"**/*.js"` → `javascript.instructions.md`
- `"**/*.py"` → `python.instructions.md`
- `"**/*.tf"` → `terraform.instructions.md`
- `"src/**"` → `src.instructions.md`
- `"test/**"` → `test.instructions.md`
- `"docs/**"` → `docs.instructions.md`
- Other patterns → `[sanitized-pattern-name].instructions.md`

### 3. Pattern Grouping Logic

**Algorithm:**
1. Collect all rules for the scope
2. Group rules by their `apply-to` patterns
3. For each unique pattern, create a separate file
4. Rules with multiple patterns get included in each applicable file
5. Global rules ("**") or rules without patterns go into `general.instructions.md` (or `user-general.instructions.md` for user scope)

**Solutions:**
- **Single Pattern**: Each file has one specific pattern → `applyTo: "pattern"`
- **Global Pattern**: Rules with "**" pattern → `applyTo: "**"`
- **No Pattern**: Rules without patterns → no YAML frontmatter or `applyTo: "**"`

**Examples:**
```yaml
# Rust-specific file (user-rust.instructions.md or rust.instructions.md)
---
applyTo: "**/*.rs"
---

# Global rules file (user-general.instructions.md or general.instructions.md)
---
applyTo: "**"
---

# Source directory file (user-src.instructions.md or src.instructions.md)
---
applyTo: "src/**"
---
```

### 4. Content Organization

**Structure for each pattern-based file:**
```markdown
---
applyTo: "pattern"
---

# Copilot Instructions (User/Repository) - Pattern Name

## General Rules from Source File A
**rule-name-1:** Rule description here
**rule-name-2:** Another rule description

## Tooling Rules from Source File B
**tool-rule-1:** Tool-specific rule
**tool-rule-2:** Another tool rule

## Coding Rules from Source File C
**coding-rule-1:** Coding guideline
**coding-rule-2:** Another coding rule
```

### 5. New Helper Functions

Create pattern-processing functions:

```powershell
function Get-RulesByPattern
{
    param([PSCustomObject[]]$Rules)
    # Group rules by their apply-to patterns
    # Handle rules with multiple patterns
    # Return grouped rules by pattern
}

function Get-PatternFileName
{
    param(
        [string]$Pattern,
        [string]$ScopeLabel
    )
    # Convert pattern to friendly filename
    # Handle common patterns (*.rs, *.ts, etc.)
    # Apply scope-specific prefixes (user- for User scope, none for Repository)
    # Sanitize unusual patterns
}

function Write-PatternRuleFile
{
    param(
        [string]$FilePath,
        [string]$Pattern,
        [string]$ScopeLabel,
        [PSCustomObject[]]$Rules
    )
    # Write file with single pattern YAML frontmatter
    # Organize rules by source file within the pattern
}
```

### 6. Pattern Consolidation Logic

**Algorithm:**
1. Collect all rules for the scope
2. Extract all unique `apply-to` patterns from rules
3. Group rules by pattern (rules with multiple patterns appear in multiple groups)
4. For each pattern group, create a dedicated file
5. Handle special cases:
   - Rules with no `apply-to` → global instructions file
   - Rules with `"**"` pattern → global instructions file
   - Rules with multiple patterns → duplicated across relevant files

### 7. Handling Multi-Pattern Rules

**Challenge:** A single rule may have multiple `apply-to` patterns

**Solution:**
- Include the rule in each applicable pattern file
- Each file maintains single-pattern YAML frontmatter
- Content organization remains clear per pattern

**Example:**
```yaml
# Rule with apply-to: ["**/*.rs", "**/*.ts"]
# For User scope, gets included in both:
# - user-rust.instructions.md (with applyTo: "**/*.rs")
# - user-typescript.instructions.md (with applyTo: "**/*.ts")
# For Repository scope, gets included in both:
# - rust.instructions.md (with applyTo: "**/*.rs")
# - typescript.instructions.md (with applyTo: "**/*.ts")
```

### 8. Backward Compatibility

- Keep `New-CopilotInstructionsLegacy` function unchanged
- Maintain same pattern-based logic for legacy mode
- Ensure existing workflows continue to work

## Implementation Steps

### Phase 1: Create New Helper Functions

1. Add `Get-RulesByPattern` function to group rules by pattern
2. Add `Get-PatternFileName` function to convert patterns to filenames
3. Add `Write-PatternRuleFile` function to write pattern-specific files
4. Implement pattern consolidation logic

### Phase 2: Update Main Function

1. Modify `New-CopilotInstructionsByScope` to use pattern-based grouping
2. Update logging messages to reflect pattern-based approach
3. Change file naming from source-file to pattern-based naming

### Phase 3: Testing

1. Test with various pattern combinations (global, specific, mixed)
2. Verify YAML frontmatter generation for each pattern
3. Test rules with multiple patterns (duplication across files)
4. Validate content organization within each pattern file
5. Test both user and repository scopes

### Phase 4: Documentation

1. Update script header comments to reflect pattern-based approach
2. Update function documentation
3. Add examples of new pattern-based output format

## Code Changes Required

### Files to Modify

- `tools/generate-llm-rules.ps1`

### Functions to Change

- `New-CopilotInstructionsByScope` - Complete rewrite for pattern-based approach
- Add `Get-RulesByPattern` - New function for pattern grouping
- Add `Get-PatternFileName` - New function for filename mapping
- Add `Write-PatternRuleFile` - New function for pattern-specific file writing

### Functions to Keep

- `New-CopilotInstructionsLegacy` - Unchanged for compatibility
- `Write-RuleFile` - Keep for other editors (Cline, Roo)

## Risk Assessment

### Low Risk Areas
- Core rule processing logic unchanged
- Legacy mode preserved
- Other editors (Cline, Roo) unaffected

### Medium Risk Areas

- Pattern-to-filename mapping logic
- Handling rules with multiple patterns (duplication)
- Content organization within pattern-specific files
- File path changes from source-based to pattern-based naming

### Testing Requirements

- Test all pattern combinations (global, specific, mixed)
- Verify pattern-to-filename mapping works correctly
- Test rules with multiple patterns appear in all relevant files
- Validate generated YAML frontmatter for each pattern
- Test both user and repository scopes
- Validate backward compatibility

## Success Criteria

1. **Functional**: All rules correctly grouped by pattern into appropriate files
2. **Format**: Valid YAML frontmatter with single pattern per file
3. **Organization**: Clear content organization within each pattern file
4. **Duplication**: Rules with multiple patterns correctly duplicated across files
5. **Naming**: Intuitive pattern-to-filename mapping
6. **Compatibility**: Legacy mode continues to work
7. **Performance**: Reduced file count and contextual relevance improves Copilot experience

## Future Considerations

- Monitor Copilot performance with pattern-based files
- Consider adding configuration option to customize pattern-to-filename mapping
- Evaluate if similar pattern-based organization beneficial for other editors
- Plan for handling complex pattern combinations
- Consider adding pattern validation to prevent conflicts

---

*Last Updated: July 5, 2025*
*Version: 1.0*
