# Refactor Copilot instruction file generation with file-level merge control

## Summary

This PR refactors the Copilot instruction file generation script to provide better control over rule consolidation and file organization.

## Changes Made

### 1. **File-level Merge Control**

- Added `merge_with_others` metadata flag to YAML rule files
- Rules marked with `merge_with_others=true` are consolidated into general instruction files
- Rules without this flag remain in separate, language-specific files

### 2. **Enhanced Script Logic**

- **Updated `Get-RulesByPattern`**: Groups rules by source file name for non-merged files instead of patterns
- **Updated `Get-PatternFileName`**: Handles file-based grouping and extracts meaningful names from source files
- **Updated `Write-PatternRuleFile`**: Properly handles merged vs separate files with appropriate YAML frontmatter

### 3. **Improved File Organization**

- **General files**: `general.instructions.md` (repo) and `user-general.instructions.md` (user) contain merged rules
- **Language-specific files**: `rust.instructions.md`, `markdown.instructions.md`, `terraform.instructions.md`, etc. for separate rules
- Users can now exclude language-specific files they don't need

## Benefits

✅ **Flexibility**: Users can choose which language-specific instruction files to include

✅ **Maintainability**: Clear separation between general and language-specific rules

✅ **Backward compatibility**: Existing workflow continues to work

✅ **User control**: File-level granularity for merge decisions

## Testing

- Verified that merged files (marked with `merge_with_others=true`) consolidate into general files
- Confirmed that language-specific files remain separate when not marked for merging
- Tested both user and repository scopes work correctly
- Generated files have proper YAML frontmatter and content organization

## Files Modified

- `tools/generate-llm-rules.ps1` - Main script with enhanced grouping logic
- `.rules-source/001-general.yaml` - Added merge metadata
- `.rules-source/002-tooling.yaml` - Added merge metadata  
- `.rules-source/050-scm.yaml` - Added merge metadata
- `.rules-source/100-workflow-guidelines.yaml` - Added merge metadata
- `.rules-source/150-coding.yaml` - Added merge metadata

## Generated Output

### Repository Scope

- `general.instructions.md` - Consolidated general rules
- `rust.instructions.md` - Rust-specific rules
- `markdown.instructions.md` - Markdown-specific rules
- `terraform.instructions.md` - Terraform-specific rules

### User Scope

- `user-general.instructions.md` - Consolidated user preferences
- `user-rust.instructions.md` - User-specific Rust rules
- `user-terraform.instructions.md` - User-specific Terraform rules
