# Repository Analysis Prompt for Copilot Coding Agent

This prompt template helps generate repository-specific instructions for GitHub Copilot coding agent. Use this template to analyze any repository and create tailored instruction sets.

## How to Use This Prompt

1. **Copy this entire prompt** into a conversation with an LLM
2. **Replace `[REPOSITORY_URL]`** with the actual repository URL
3. **Run the analysis** to generate repository-specific Copilot instructions
4. **Save the output** to `.github/instructions/` in the target repository

---

## Repository Analysis Prompt

Please analyze the repository at `[REPOSITORY_URL]` and generate comprehensive repository-specific instructions for GitHub Copilot coding agent. Create instructions that will help Copilot understand the project's patterns, conventions, and requirements.

### Analysis Framework

Please examine the repository and provide detailed analysis in the following areas:

#### 1. Basic Repository Information

- Repository name and primary purpose
- Main programming languages used (with percentages if possible)
- Project type (web application, library, CLI tool, mobile app, etc.)
- Target audience (developers, end-users, both)
- Maturity level (experimental, stable, production-ready)

#### 2. Architecture and Patterns

- Overall architecture pattern (MVC, microservices, monolithic, etc.)
- Design patterns commonly used in the codebase
- Module/package organization structure
- Data flow patterns
- Key architectural decisions and their rationale

#### 3. Coding Standards and Conventions

- Code formatting and style guidelines
- Naming conventions for:
  - Variables and functions
  - Files and directories
  - Classes and interfaces
  - Constants and enumeration types
- Comment and documentation standards
- Import/include organization patterns

#### 4. Testing Approach

- Testing frameworks and libraries used
- Test file organization and naming patterns
- Testing strategies (unit, integration, e2e)
- Code coverage expectations
- Mock/stub patterns and practices
- Test data management approaches

#### 5. Build and Development Workflow

- Build tools and configuration files
- Development environment setup requirements
- Dependency management approach
- CI/CD pipeline structure and requirements
- Release and versioning strategies
- Development workflow (branching, PR process, etc.)

#### 6. Technology Stack and Dependencies

- Primary frameworks and libraries
- Database technologies and ORM/ODM usage
- External services and API integrations
- Development vs production configurations
- Performance considerations and optimizations

#### 7. Project-Specific Patterns

- Common error handling patterns
- Logging and monitoring approaches
- Configuration management patterns
- Security practices and considerations
- Data validation and sanitization approaches
- API design patterns (if applicable)

### Output Format

Based on your analysis, create repository-specific Copilot instructions in the following format:

```markdown
---
applyTo: "**"
---

# Copilot Instructions (Repository)

## Project Overview
[Brief description of the project and its purpose]

## Architecture Guidelines
[Key architectural principles and patterns to follow]

## Coding Standards
[Specific coding conventions and standards]

## Testing Requirements
[Testing approaches and requirements]

## Development Workflow
[Build, development, and deployment considerations]

## Technology-Specific Guidelines
[Framework/library-specific best practices]

## Common Patterns
[Project-specific patterns and practices to follow]

## Error Handling and Logging
[Error handling strategies and logging requirements]

## Performance Considerations
[Performance optimization guidelines]

## Security Requirements
[Security practices and considerations]
```

### Analysis Instructions

1. **Be Specific**: Provide concrete examples from the actual codebase
2. **Focus on Patterns**: Identify recurring patterns that Copilot should replicate
3. **Include Context**: Explain the reasoning behind patterns and conventions
4. **Be Actionable**: Create instructions that Copilot can directly apply
5. **Consider Scale**: Account for the project's size and complexity
6. **Include Examples**: Provide code snippets where helpful
7. **Address Edge Cases**: Include guidance for common edge cases or exceptions

### Repository Analysis Request

Please analyze the repository at `[REPOSITORY_URL]` using this framework and generate the repository-specific Copilot instructions. Include specific examples from the codebase and ensure the instructions are tailored to this particular project's needs and conventions.

---

## Example Usage

Here's how to use this prompt:

1. Replace `[REPOSITORY_URL]` with: `https://github.com/user/repo`
2. Paste the entire prompt into your LLM conversation
3. Review the generated instructions
4. Save to `.github/instructions/repository-analysis.instructions.md`
5. Customize further if needed for your specific use case

## Tips for Best Results

- **Public repositories**: Work best as LLMs can access and analyze them directly
- **Large repositories**: Consider analyzing specific modules or directories
- **Complex projects**: May need multiple analysis sessions for different components
- **Legacy code**: Ask the LLM to identify modernization opportunities
- **Documentation**: Include analysis of existing documentation and README files

## Integration with Copilot

These generated instructions will:

- Guide Copilot to follow project-specific patterns
- Help maintain consistency across the codebase
- Ensure new code aligns with existing conventions
- Provide context for architecture decisions
- Support better code suggestions and completions
