# Repository Analysis & Instruction Generation Prompt

## 🎯 Task

You are an expert software architect and documentation specialist tasked with analyzing a repository and generating
comprehensive instruction files for GitHub Copilot. Your goal is to create detailed documentation that describes the
repository's purpose, architecture, coding practices, and standards.

## 📋 Analysis Scope

Perform a thorough analysis of the repository and generate instruction files covering the following areas:

### 1. Repository Overview

- **Primary purpose and goals** of the repository
- **Target audience** (developers, users, etc.)
- **Core functionality** and main features
- **Business domain** or technical area
- **Maturity level** (experimental, production-ready, etc.)

### 2. Technical Architecture

- **Architecture patterns** used (microservices, monolith, layered, etc.)
- **System design principles** followed
- **Key architectural decisions** and rationale
- **Data flow** and component interactions
- **External dependencies** and integrations

### 3. Technology Stack

- **Primary programming languages** and versions
- **Frameworks and libraries** used
- **Build tools** and automation
- **Database technologies** (if applicable)
- **Infrastructure and deployment** technologies
- **Development tools** and IDE configurations

### 4. Code Organization & Structure

- **Directory structure** and organization principles
- **Module/package** naming conventions
- **File naming** patterns
- **Code layering** (presentation, business, data, etc.)
- **Separation of concerns** approach

### 5. Coding Standards & Conventions

- **Code formatting** rules and style guides
- **Naming conventions** for variables, functions, classes, etc.
- **Comment and documentation** standards
- **Error handling** patterns
- **Logging and monitoring** practices
- **Performance considerations** and guidelines

### 6. Testing Strategy

- **Testing frameworks** and tools used
- **Test organization** and structure
- **Test naming** conventions
- **Coverage requirements** and goals
- **Test data** management practices
- **Integration and end-to-end** testing approaches

### 7. Build & Deployment

- **Build process** and automation
- **Dependency management** practices
- **Environment configuration** (dev, staging, prod)
- **Deployment strategies** and processes
- **CI/CD pipeline** structure
- **Release management** practices

### 8. Development Workflow

- **Git workflow** and branching strategy
- **Code review** process and requirements
- **Development environment** setup
- **Contribution guidelines** and processes
- **Issue tracking** and project management

## 🔍 Analysis Instructions

### Step 1: Repository Exploration

1. **Examine the root directory** for README files, configuration files, and documentation
2. **Analyze the directory structure** to understand the project organization
3. **Review key files** such as:
   - `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`
   - Package files (`package.json`, `requirements.txt`, `Cargo.toml`, etc.)
   - Configuration files (`.gitignore`, build configs, CI/CD files)
   - License and legal files

### Step 2: Code Analysis

1. **Examine source code** in main directories
2. **Identify patterns** in file organization and naming
3. **Review code style** and formatting consistency
4. **Analyze imports/dependencies** to understand technology stack
5. **Look for architectural patterns** in the codebase

### Step 3: Documentation Review

1. **Read existing documentation** thoroughly
2. **Identify documentation gaps** or inconsistencies
3. **Note any coding standards** or guidelines mentioned
4. **Review API documentation** (if applicable)

### Step 4: Testing & Quality Analysis

1. **Examine test directories** and test files
2. **Identify testing frameworks** and patterns used
3. **Review CI/CD configurations** for quality gates
4. **Look for linting and formatting** tool configurations

## 📝 Output Format

Generate instruction files using the following structure:

### Repository Description Instructions

Create a comprehensive instruction file that includes:

```markdown
# Repository Instructions

## Overview
[Concise description of the repository's purpose and goals]

## Architecture
[Description of architectural patterns and design principles]

## Technology Stack
[List of technologies, frameworks, and tools used]

## Coding Standards
[Detailed coding conventions and style guidelines]

## Development Guidelines
[Instructions for developers working on this codebase]

## Testing Requirements
[Testing standards and practices to follow]

## Build & Deployment
[Instructions for building and deploying the application]
```

### Key Principles to Follow

1. **Be Specific**: Provide concrete examples and clear guidelines
2. **Be Actionable**: Give instructions that developers can immediately follow
3. **Be Consistent**: Ensure all recommendations align with existing practices
4. **Be Comprehensive**: Cover all major aspects of development in this repository
5. **Be Current**: Base instructions on the current state of the repository

### Output Guidelines

- **Use clear, concise language** that developers can easily understand
- **Include code examples** where helpful to illustrate patterns
- **Reference specific files or directories** when providing examples
- **Organize information logically** with proper headings and structure
- **Prioritize the most important guidelines** first
- **Avoid contradicting existing practices** unless they are clearly problematic

## 🚀 Getting Started

1. **Clone or examine** the repository you need to analyze
2. **Follow the analysis instructions** systematically
3. **Generate the instruction file** using the specified format
4. **Review and refine** the instructions for clarity and completeness
5. **Ensure alignment** with existing repository practices and documentation

---

**Note**: This prompt is designed to help GitHub Copilot generate repository-specific instruction files that will improve
code suggestions and maintain consistency with project standards.
