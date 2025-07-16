---
mode: agent
---

## 🎯 Task

You are an expert DevOps engineer and automation specialist tasked with analyzing a repository and generating a
comprehensive GitHub Actions workflow file for development environment setup. Your goal is to create a workflow
that enables GitHub Copilot and other developers to quickly initialize and configure the development environment
for any repository.

## 📋 Workflow Requirements

Generate a GitHub Actions workflow file named `.github/workflows/copilot-setup-steps.yml` that includes a single
job called `copilot-setup-steps`. This workflow should handle comprehensive environment initialization covering the
following areas:

### 1. Development Environment Setup

- **Operating system** detection and configuration
- **Runtime environments** (Node.js, Python, Java, .NET, etc.)
- **Package managers** (npm, pip, cargo, maven, etc.)
- **Environment variables** and configuration
- **System dependencies** and tools

### 2. Dependencies Installation

- **Primary dependencies** from package files
- **Development dependencies** for tooling
- **Global tools** and utilities
- **Optional dependencies** for specific features
- **Cache management** for faster subsequent runs

### 3. Testing Environment Configuration

- **Test frameworks** setup and configuration
- **Test databases** or mock services
- **Test data** initialization
- **Coverage tools** configuration
- **Performance testing** tools (if applicable)

### 4. Code Quality Tools Setup

- **Linters** and static analysis tools
- **Code formatters** and style checkers
- **Security scanners** and vulnerability checks
- **Documentation generators** and validators
- **Pre-commit hooks** installation

### 5. Repository-Specific Setup

- **Build artifacts** preparation
- **Configuration files** generation
- **Database migrations** or schema setup
- **Service dependencies** initialization
- **Custom tooling** or scripts execution

## 🔍 Repository Analysis Instructions

### Step 1: Technology Stack Detection

1. **Identify primary languages** by examining:
   - File extensions in the repository
   - Package files (`package.json`, `requirements.txt`, `Cargo.toml`, `pom.xml`, etc.)
   - Configuration files (`.nvmrc`, `runtime.txt`, `Dockerfile`, etc.)
   - Build files (`Makefile`, `build.gradle`, `CMakeLists.txt`, etc.)

2. **Determine runtime requirements**:
   - Language versions and compatibility
   - Framework dependencies
   - System-level requirements

### Step 2: Build System Analysis

1. **Examine build configurations**:
   - Build scripts in package files
   - Dedicated build tools (webpack, rollup, gradle, etc.)
   - Compilation requirements
   - Asset processing needs

2. **Identify automation tools**:
   - Task runners (npm scripts, make targets, etc.)
   - CI/CD configurations for reference
   - Development servers or watch modes

### Step 3: Testing Infrastructure Review

1. **Discover testing frameworks**:
   - Test configuration files
   - Test directories and file patterns
   - Testing dependencies in package files
   - Mock or fixture requirements

2. **Analyze quality tools**:
   - Linter configurations (`.eslintrc`, `pylint.cfg`, etc.)
   - Formatter settings (`.prettierrc`, `black.toml`, etc.)
   - Static analysis tools configuration

### Step 4: Development Workflow Assessment

1. **Review development scripts**:
   - Available npm/yarn scripts
   - Make targets or similar automation
   - Development server configurations
   - Database setup scripts

2. **Examine documentation**:
   - Setup instructions in README files
   - Contributing guidelines
   - Development environment documentation

## 📝 Workflow Generation Guidelines

### Workflow Structure

Generate a workflow using this template structure:

```yaml
name: Copilot Development Environment Setup

# Automatically run the setup steps when they are changed to allow for easy validation, and
# allow manual testing through the repository's "Actions" tab
on:
  workflow_dispatch:
  push:
    paths:
      - .github/workflows/copilot-setup-steps.yml
  pull_request:
    paths:
      - .github/workflows/copilot-setup-steps.yml

  # Set the permissions to the lowest permissions possible needed for your steps.
  # Copilot will be given its own token for its operations.
  permissions:
    # If you want to clone the repository as part of your setup steps, for example to install dependencies,
    # you'll need the `contents: read` permission. If you don't clone the repository in your setup steps, Copilot
    # will do this for you automatically after the steps complete.
    contents: read

jobs:
  copilot-setup-steps:
    name: Setup Development Environment
    runs-on: ubuntu-latest  # Adjust based on repository requirements

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      # Environment setup steps based on repository analysis
      # Dependencies installation
      # Testing environment configuration
      # Code quality tools setup
      # Repository-specific initialization
```

### Key Principles to Follow

1. **Be Repository-Specific**: Tailor the workflow to the actual technologies and tools used
2. **Be Comprehensive**: Cover all aspects needed for development
3. **Be Efficient**: Use caching and optimization strategies
4. **Be Reliable**: Include error handling and validation steps
5. **Be Flexible**: Support different setup scopes (basic, full, testing)
6. **Be Documented**: Include clear comments explaining each step

### Required Workflow Features

#### Input Parameters

- **setup_scope**: Allow different levels of setup (basic, full, testing)
- **Additional inputs** as needed for repository-specific configuration

#### Cache Management

- **Dependency caches** for package managers
- **Build artifact caches** where applicable
- **Tool caches** for downloaded utilities

#### Error Handling

- **Validation steps** to verify successful setup
- **Fallback strategies** for optional components
- **Clear error messages** with troubleshooting guidance

#### Output Information

- **Setup summary** with installed versions
- **Next steps** for developers
- **Troubleshooting tips** for common issues

## 🔧 Technology-Specific Templates

### Node.js/JavaScript Projects

```yaml
- name: Setup Node.js
  uses: actions/setup-node@v4
  with:
    node-version-file: '.nvmrc'  # or specific version
    cache: 'npm'  # or 'yarn', 'pnpm'

- name: Install dependencies
  run: npm ci  # or yarn install --frozen-lockfile
```

### Python Projects

```yaml
- name: Setup Python
  uses: actions/setup-python@v4
  with:
    python-version-file: '.python-version'  # or specific version
    cache: 'pip'

- name: Install dependencies
  run: |
    python -m pip install --upgrade pip
    pip install -r requirements.txt
```

### Java Projects

```yaml
- name: Setup Java
  uses: actions/setup-java@v4
  with:
    java-version-file: '.java-version'  # or specific version
    distribution: 'temurin'
    cache: 'maven'  # or 'gradle'

- name: Install dependencies
  run: ./mvnw dependency:resolve  # or ./gradlew dependencies
```

### Rust Projects

```yaml
- name: Setup Rust
  uses: actions-rs/toolchain@v1
  with:
    toolchain: stable
    components: rustfmt, clippy
    override: true

- name: Cache cargo registry
  uses: actions/cache@v3
  with:
    path: ~/.cargo/registry
    key: ${{ runner.os }}-cargo-registry-${{ hashFiles('**/Cargo.lock') }}
```

## 🚀 Analysis and Generation Process

### Step 1: Repository Analysis

1. **Examine the repository structure** systematically
2. **Identify all technologies** and their versions
3. **Map dependencies** and build requirements
4. **Document setup complexity** and special requirements

### Step 2: Workflow Design

1. **Plan the setup sequence** logically
2. **Optimize for performance** with caching
3. **Include error handling** and validation
4. **Design for flexibility** with input parameters

### Step 3: Workflow Generation

1. **Generate the complete workflow file**
2. **Include comprehensive comments** explaining each step
3. **Validate the workflow structure** and syntax
4. **Test compatibility** with repository requirements

### Step 4: Documentation

1. **Create setup instructions** for using the workflow
2. **Document any prerequisites** or special requirements
3. **Provide troubleshooting guidance** for common issues
4. **Include examples** of different setup scenarios

## 📋 Output Format

Generate the workflow file with:

1. **Complete YAML structure** ready for `.github/workflows/copilot-setup-steps.yml`
2. **Detailed comments** explaining each step and decision
3. **Input parameters** for different setup scenarios
4. **Comprehensive setup steps** covering all identified requirements
5. **Error handling** and validation steps
6. **Performance optimizations** with appropriate caching

### Validation Checklist

Before finalizing the workflow, ensure:

- [ ] All detected technologies are properly configured
- [ ] Dependencies are installed in the correct order
- [ ] Caching is implemented for performance
- [ ] Error handling covers potential failure points
- [ ] The workflow is compatible with GitHub Actions syntax
- [ ] Setup steps are documented and explained
- [ ] Different setup scopes are properly supported

---

**Note**: This prompt is designed to help GitHub Copilot generate repository-specific GitHub Actions workflows that automate development environment setup, making it easier for developers and AI assistants to work with any codebase.
