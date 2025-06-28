# Contributing to LLM Prompt Engineering

Thank you for your interest in contributing to this project! This guide will help you get started.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Install PowerShell and the required modules:

   ```powershell
   Install-Module powershell-yaml
   ```

## Project Structure

- **`modes/`**: Custom AI assistant modes for different development tasks
- **`prompts/`**: Reusable prompt templates for common LLM interactions
- **`specs/`**: Technical specifications and design documents
- **`tools/`**: Automation scripts for generating LLM configuration files
- **`output/`**: Generated files (do not edit directly)

## Making Changes

### Adding New Modes

1. Create a new markdown file in the `modes/` directory
2. Follow the existing format with YAML frontmatter for metadata
3. Include clear descriptions of the mode's purpose and capabilities

### Adding New Prompts

1. Create a new markdown file in the `prompts/` directory
2. Use descriptive filenames that indicate the prompt's purpose
3. Include examples where helpful

### Modifying Tools

1. Test your changes locally before submitting
2. Ensure PowerShell scripts are cross-platform compatible
3. Update documentation if you change script parameters or behavior

## Testing

Before submitting changes:

1. Run the rule generation tool to ensure it works:

   ```powershell
   .\tools\generate-llm-rules.ps1
   ```

2. Verify generated files are properly formatted
3. Test any new modes or prompts with your preferred LLM tools

## Submitting Changes

1. Create a meaningful commit message
2. Push to your fork
3. Create a pull request with:
   - Clear description of what you changed
   - Why the change is needed
   - Any testing you performed

## Questions?

If you have questions about contributing, please:

- Check the specifications in `specs/` for technical details
- Review existing files for examples
- Open an issue for discussion

We appreciate your contributions to making LLM prompt engineering more accessible and standardized!
