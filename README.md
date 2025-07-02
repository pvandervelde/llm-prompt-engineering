# LLM Prompt Engineering

A practical solution for managing AI coding assistant configurations across multiple tools. Instead of maintaining
separate rule files for GitHub Copilot, Cline, and Roo Code, this repository lets you write once in YAML and generate
configurations for all of them.

## What You Get

### Rule Management

- Write coding rules once in YAML, generate configs for all your AI tools
- Separate user-specific preferences from project-specific requirements
- Automatic filtering so each tool only gets relevant instructions

### Repository Analysis

- Prompts that help AI assistants understand your codebase architecture
- Automated generation of project-specific instruction files
- Support for analyzing tech stack, coding patterns, and project structure

### Workflow Automation

- GitHub Actions workflows for setting up development environments
- Technology-specific templates (Node.js, Python, Java, Rust, etc.)
- Automated dependency installation and tool configuration

### Advanced Prompting

- Multi-persona review system for evaluating ideas from different expert perspectives
- Conversation templates for maintaining context across AI sessions
- Custom AI modes for specialized tasks (like architecture planning)

## How It Works

The main idea is simple: define your coding rules once in YAML files, then generate the specific formats each tool needs.

### The Generation Process

1. **Write rules in YAML**: Store all your coding guidelines in `.rules-source/` directory
2. **Run the generator**: PowerShell script processes YAML and creates tool-specific configs
3. **Copy to projects**: Generated files go where each tool expects them

### Scope Separation for Copilot

GitHub Copilot supports both user-level and repository-level instructions. This matters because:

- **User scope**: Your personal coding style, general preferences
- **Repository scope**: Project-specific patterns, architecture decisions, team conventions

The generator automatically separates rules based on their `scope` field in YAML.

### Multi-Tool Support

Each AI tool has different file format requirements:

- **GitHub Copilot**: Markdown files in `.github/instructions/` or VSCode profile
- **Cline**: `.clinerules` file in project root
- **Roo Coder**: Markdown files in `.roo/` directory

The generator handles all these formats automatically.

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

   **For GitHub Copilot:**
   - **Repository-specific**: Copy files from `output/copilot/.github/instructions/` to your project's `.github/instructions/` directory
   - **User-specific**: Copy files from `output/copilot/vscode-profile/` to your VS Code profile directory
   - **Legacy support**: Files also available in `output/.github/` for backward compatibility

   **For Cline:** Copy files from `output/.clinerules/` to your project root

   **For Roo Code:** Copy files from `output/.roo/` to your project's `.roo/` directory

4. **Use repository analysis prompts** (optional)

   Use the prompts to analyze codebases and generate workflows:
   - `prompts/repository-description-instructions-prompt.md` - Analyze any codebase
   - `prompts/copilot-setup-workflow-prompt.md` - Generate GitHub Actions workflows

## What's in Here

This repository contains several types of resources:

### Rules and Generation (`.rules-source/`, `tools/`)

The core functionality - YAML rule definitions and the PowerShell script that generates tool-specific configurations.

### Repository Analysis (`prompts/`)

Prompts designed to help AI assistants understand your codebase:

- Comprehensive repository analysis that covers architecture, tech stack, and coding patterns
- GitHub Actions workflow generation for automated environment setup
- Support for multiple programming languages and frameworks

### Advanced Prompting (`prompts/`, `modes/`)

Specialized prompt templates for common development scenarios:

- Multi-persona review system with expert perspectives from different roles
- Conversation templates that maintain context across sessions
- Custom AI modes like "Architect" for system design work

### Generated Output (`output/`)

The script generates appropriately formatted files for each tool:

- **GitHub Copilot**: Separate user vs repository instructions, legacy format support
- **Cline**: `.clinerules` files with mode-specific filtering
- **Roo Coder**: Organized rule directories with proper structure

## Project Structure

```text
├── .rules-source/          # YAML source files for LLM rules
├── modes/                  # Custom AI assistant modes
│   ├── architect.md        # Software architecture specialist mode
│   └── README.md          # Mode documentation
├── prompts/               # Reusable prompt templates
│   ├── conversation-continuation.md      # Context preservation templates
│   ├── copilot-setup-workflow-prompt.md # GitHub Actions workflow generation
│   ├── group-personas.md                # Multi-persona review system
│   ├── repository-description-instructions-prompt.md # Repository analysis
│   └── review-problem-with-group.md     # Group review templates
├── specs/                 # Technical specifications
│   └── llm-rules-source-of-truth-spec.md # Architecture documentation
├── tools/                 # Automation scripts
│   └── generate-llm-rules.ps1          # Main generation script
├── workflows/             # Workflow templates
│   └── copilot/          # Copilot-specific workflow templates
└── output/               # Generated LLM configuration files
    ├── .github/          # Legacy Copilot instructions (backward compatibility)
    ├── .clinerules/      # Cline rule files
    ├── .roo/            # Roo Coder rule files
    └── copilot/         # Advanced Copilot configuration
        ├── .github/instructions/     # Repository-specific instructions
        └── vscode-profile/          # User-specific instructions
```

## Documentation

### Getting Started

- [Examples and Usage Guide](./EXAMPLES.md) - Detailed usage examples and patterns
- [Contributing Guidelines](./CONTRIBUTING.md) - How to add new rules, modes, and prompts

### Technical Details

- [LLM Rules Specification](./specs/llm-rules-source-of-truth-spec.md) - Architecture and design decisions

### Prompt Templates

- [Repository Analysis](./prompts/repository-description-instructions-prompt.md) - Analyze any codebase to generate instruction files
- [Workflow Generation](./prompts/copilot-setup-workflow-prompt.md) - Create GitHub Actions workflows for environment setup
- [Group Review](./prompts/review-problem-with-group.md) - Get feedback from multiple expert perspectives
- [Conversation Continuation](./prompts/conversation-continuation.md) - Maintain context across AI sessions

### AI Assistant Modes

- [Modes Overview](./modes/README.md) - Available modes and how to use them
- [Architect Mode](./modes/architect.md) - System design and architecture planning

## Contributing

Contributions are welcome! Please read the technical specifications in the `specs/` directory to understand the architecture before making changes.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
