# LLM Rules Source of Truth Specification

## Title

Establishing a Single Source of Truth for LLM Rules with Multi-Format Generation and Mode-Specific Filtering

## Problem Description

Multiple LLMs (e.g., Copilot, Cline, Roo code) require rules to be provided in different file formats
and locations. Some LLMs have multiple modes that require different subsets of rules. Currently,
rules are duplicated or scattered, leading to inconsistency and maintenance overhead.

## Surrounding Context

- Copilot expects a single markdown file `.github/copilot-instructions.md` with all rules.
- Cline expects a `.clinerules` file.
- Roo code expects either a directory `.roo/rules/` with markdown files for all modes or mode-specific
  directories `.roo/rules-<MODE>/`.
- Rules are currently maintained in multiple places, causing duplication.
- Reducing context size for LLMs with modes requires sending only relevant rules per mode.

## Proposed Solution

### Design Goals

- Centralize all LLM rules in a single source of truth (SoT).
- Use metadata tagging to specify which rules apply to which LLMs and modes.
- Automate generation of required rule files/formats from the SoT.
- Support mode-specific filtering to reduce context size.
- Enable easy local and CI execution of the generation process.

### Design Constraints

- The SoT should be human-readable and easy to maintain.
- The generation tooling should be cross-platform friendly; PowerShell is chosen for local and CI compatibility.
- The solution should integrate with GitHub Actions for automation.

### Design Decisions

- Use a dedicated directory `.rules-source/` for the SoT.
- Use YAML files to store the source rules with metadata.
- Implement a PowerShell script to parse, filter, and generate rule files.
- Create a GitHub Actions workflow to run the script on code changes.

### Alternatives Considered

- Using JSON or YAML files for SoT instead of markdown.
- Using other scripting languages (Python, Node.js).
- Manual maintenance of rule files (rejected due to duplication risk).

## Design

### Architecture

```mermaid
flowchart TD
  A[.rules-source/ (Source of Truth)] --> B[PowerShell Generation Script]
  B --> C1[.github/copilot-instructions.md]
  B --> C2[.clinerules]
  B --> C3[.roo/rules/ or .roo/rules-<MODE>/]
  C3 --> D[Mode-specific Rule Files]
```

### Data Flow

1. The PowerShell script reads all YAML files in `.rules-source/`.
2. It filters and aggregates rules per LLM and mode.
3. It writes the output files in the required formats and locations.

### Module Breakdown

- **Source Reader:** Reads and parses YAML files with metadata.
- **Filter Module:** Filters rules by LLM and mode.
- **Output Generator:** Writes files for each LLM and mode.
- **CLI Interface:** Accepts parameters for selective generation (optional).

### Other Relevant Details

- Rules without explicit LLM or mode metadata apply to all.
- The script overwrites existing output files.
- The GitHub Actions workflow triggers on push and pull request events.

## Source Directory Layout and Rule Examples

### Directory Layout

The source of truth directory `.rules-source/` should contain markdown files with rules. Files
should be organized by logical grouping or topics rather than by LLM, since metadata within the
files will specify applicability.

Example structure:

```
.rules-source/
├── general.yaml
├── development.yaml
├── source-control.yaml
├── debugging.yaml
```

### Rule Metadata Format

Each YAML file or section looks like:

```yaml
---
- name: <RULE_NAME>
  editors:
    - name: copilot
      modes: [<MODE1>, <MODE2>, ...]
    - name: cline
      modes: [<MODE1>, <MODE2>, ...]
    - name: roo
      modes: [<MODE1>, <MODE2>, ...]
  text: |
    <MARKDOWN_RULE_TEXT>
---
```

- `name`: A unique identifier for the rule.
- `editors`: A list of LLMs and their applicable modes.
  - Each entry specifies the LLM name and a list of modes it applies to.
- `text`: The rule text in markdown format.
- If omitted, the rule applies to all LLMs or modes.

## Conclusion

This specification outlines a maintainable, automated approach to managing LLM rules with a single source of truth, supporting multiple LLMs and modes, and integrating with CI for continuous updates.
