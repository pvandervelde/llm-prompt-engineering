# LLM Prompt Engineering

A collection of prompt engineering resources, rules, and tools for various Large Language Model (LLM) editors and assistants including GitHub Copilot, Cline, and Roo Coder.

## Overview

This repository provides:

- **Centralized LLM Rules Management**: A single source of truth for LLM rules with automatic generation for different tools
- **Custom Modes**: Specialized AI assistant modes for different development tasks
- **Prompt Templates**: Reusable prompt patterns for common LLM interactions
- **Automation Tools**: PowerShell scripts for generating and managing LLM configuration files

## Quick Start

1. **Clone the repository**

   ```bash
   git clone https://github.com/pvandervelde/llm-prompt-engineering.git
   cd llm-prompt-engineering
   ```

2. **Generate LLM rules** (requires PowerShell and PowerShell-YAML module)

   ```powershell
   Install-Module powershell-yaml
   .\tools\generate-llm-rules.ps1
   ```

3. **Use the generated files**
   - Copy files from `output/.github/` to your project's `.github/` directory for Copilot
   - Copy files from `output/.clinerules/` to your project root for Cline
   - Copy files from `output/.roo/` to your project's `.roo/` directory for Roo Coder

## Repository Structure

```text
├── modes/              # Custom AI assistant modes
├── prompts/            # Reusable prompt templates
├── specs/              # Technical specifications
├── tools/              # Automation scripts
└── output/             # Generated LLM configuration files
```

## Documentation

- [Examples and Usage Guide](./EXAMPLES.md) - Detailed usage examples and tutorials
- [Modes](./modes/README.md) - Custom AI assistant modes
- [LLM Rules Specification](./specs/llm-rules-source-of-truth-spec.md) - Technical design for centralized rules management
- [Contributing Guidelines](./CONTRIBUTING.md) - How to contribute to this project

## Contributing

Contributions are welcome! Please read the technical specifications in the `specs/` directory to understand the architecture before making changes.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
