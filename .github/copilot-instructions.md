# Copilot instructions

All rules are to be followed in all projects. The rules are divided into categories for better organization.
Rules in this file are prefixed with `general-` to indicate that they are general rules.

## General

### Behaviour

1. **general-mention-rules-used**: Every time you choose to apply a rule(s), explicitly state the
   rule(s) in the output. You can use the `rule` tag to do this. For example, `#rule: rule_name`.
   This will help in understanding the reasoning behind the decisions made in the code.
2. **general-mention-knowledge**: List all assumptions and uncertainties you need to clear up before
   completing this task.
3. **general-confidence-check**: Rate confidence (1-10) before saving files, after saving, after
   rejections, and before task completion

### Tool use

1. **general-tool-use-os**: Use operating system relevant tools when possible. For example, use
   `bash` on Linux and MacOS, and `powershell` on Windows
2. **general-tool-use-file-search**: When searching for files in the workspace make sure to also
   search the directories starting with a dot (e.g. `.github`, `.vscode`, etc.). But skip the
   `.git` directory.

## Tool Guidelines

All rules are to be followed in all projects. The rules are divided into categories for better organization.
Rules in this file are prefixed with `tool-` to indicate that they are tool rules.

### General

1. **tool-proactive**: Tools are not optional utilities but essential components of the thinking process.
   - Initiate appropriate tool usage without explicit human prompting
   - Treat tools as extensions of analytical capabilities
   - Multiple tools should be used in parallel when beneficial

2. **tool-decision-making**: When choosing tools, consider:
   - Primary goal of the current task
   - Potential for multiple tool synergy
   - Value of combined tool outputs
   - Balance between depth and response time
   - Previous tool usage patterns in the conversation
   - Query type and required verification level

### Available Tools

The following tools are available for use in this project. Use them according to the guidelines.

#### General

1. Sequential Thinking is the primary entry point for all tasks. Use it liberally to guide the process.
   - Automatically begins with each new topic or request
   - Guides the selection and integration of other tools
   - Core Functions:
     - Problem decomposition
     - Tool selection strategy
     - Process monitoring
     - Course correction
     - Integration of multiple tool outputs

#### Search

A number of search tools are available for use. Use them according the following
table:

| Query Type | Primary Tools | Secondary Tools | Verification |
|------------|--------------|-----------------|--------------|
| Factual | Tavily QnA + Grounding | Brave Search | Required |
| Technical | Perplexity + Tavily | Jina.ai | Optional |
| Current Events | Brave + Tavily | Perplexity | Required |
| Research | Tavily + Brave | All Others | Required |
| Source Analysis | Tavily | Grounding | Required |
| Quick Answers | Tavily QnA | Perplexity | Optional |

**Grounding** is the process of verifying and validating information from multiple sources.

- Use grounding to ensure accuracy and reliability of information
- Cross-reference findings from different tools
- Document grounding results and sources

##### Available Search Tools

1. Brave Search is the primary search tool for all queries.
   - Use for general searches and current events
   - Provides a wide range of information

2. Tavily Search is the secondary search tool for all queries.
   - Use for specific queries and to complement Brave Search
   - Provides additional context and information
   - Use for background information and contextual searches

3. Perplexity is an enhanced search tool for technical queries.
   - Use for in-depth technical searches and research
   - Provides detailed information and analysis
   - Use for complex queries requiring technical expertise

## Source control Guidelines

All rules are to be followed in all projects. The rules are divided into categories for better organization.
Rules in this file are prefixed with `scm-` to indicate that they are source control rules.

### Assumptions

1. Assume that the GitHub CLI is available and signed in

### Branches

1. **scm-create-branch**: Before making any changes to the codebase, check that you are on the
  correct branch. Code is *never* directly committed to the `main` or `master` branches. If no
  suitable branch exist create a new branch for your changes and switch to that branch. If
  you cannot create a branch, notify the user.
2. **scm-branch-naming**: The branch name should be a brief summary of the changes being made. Branch
   names should be in lowercase and use hyphens to separate words. For example, `fix-bug-in-login-page`
   or `feature-add-new-user`.

### Committing

1. **scm-staging**: Before committing any code, ensure that all changes are staged and ready to be committed.
   Use `git add .` to stage all changes.
2. **scm-commit-message**: Use the following format for commit messages: `type(scope): subject`. The
   type should be one of the following: `feat`, `fix`, `chore`, `docs`, `style`, `refactor`, `perf`,
   `test`. The scope should be the name of the module or component being changed. The subject should
   be a short description of the change.
3. **scm-include-workitem**: All commits should include a reference to the work item being
   addressed. This can be done by including the issue number at the end of the commit message. For
   example: `fix(login): fix bug in login page #123`. Use one of the following issue references:
   `fixes`, `closes`, `resolves`, `references` or `related to`. The issue reference should be followed
   by the issue number.

### Pull Requests

1. **scm-git-pull-request-content**: Create a pull request (PR) for all changes made to the codebase.
   The PR should include a description which changes were made, why the changes were made, links to
   relevant ssue numbers, results from testing, and any other relevant information. Follow the pull
   request template if there is one.
2. **scm-git-pull-request-review**: All pull requests should be reviewed by at least one other developer
   before being merged into the main branch. Additionally we always invite copilot on the review if
   available.

## Development Guidelines

All rules are to be followed in all projects. The rules are divided into categories for better organization.
Rules in this file are prefixed with `dev-` to indicate that they are development rules.

### Design

1. **dev-design-spec-issue**: Create an issue for the creation of design document. The issue should describe
   why we're making the design document. Follow the issue template in the creation of the issue.
2. **dev-design-before-code**: Before writing any code for a new feature or bug fix, create a design document
   that outlines the architecture, data flow, and any other relevant details. This will help ensure that
   the code is well-structured and maintainable. Design documents are placed in the `specs` directory of the
   repository.
3. **dev-design-spec-layout**: The design document should be in markdown format. Follow the markdown
   style guide and ensure that lines are no longer than 100 characters. It should follow the
   following structure:
   - Title
   - Description
   - Design
     - Architecture
     - Data flow
     - Other relevant details
   - Conclusion
4. **dev-design-issues**: From the design document we create the implementation issues. The issues should be
   created in the same way as the design document. The issues should be linked to the design document.
   Each issue should be complete and small enough that it can be completed in one go.
5. **dev-splitting-large-tasks**: If a task is too large to complete in one go, break it down into smaller
   tasks. Create issues for each task and link them together. This will help keep the codebase organized and
   make it easier to track progress.

### Coding

1. **dev-code-tasks**: Coding starts with an implementation issue. During the session we only solve the
   implementation issue. If we find other changes that we want to make, we create new issues for
   them.
2. **dev-code-style**: All code should be easy to understand and maintain. Use clear and descriptive
   names for variables, functions, and classes. Always follow the coding standards and best practices
   for the programming language being used.

### Testing standards

1. **dev-unit-test-coverage**: All business logic should be covered by unit tests. We're aiming to cover
   all input and output paths of the code. This includes edge cases and error handling. Use coverage
   tools to measure the test coverage and use mutation testing to ensure that the tests are
   effective.

### Documentation

1. **dev-documentation**: The coding task is not complete without documentation. All code should be
   well-documented. Use comments to explain the purpose of complex code and to provide context for
   future developers. Use docstrings to document functions, classes, and modules. The documentation
   should be clear and concise.
2. **dev-documentation-standards**: Follow the documentation standards and best practices for the
   programming language being used.

### Continuous Integration & Delivery

1. **dev-ci**: All changes should be checked with a continuous integration (CI) tool before being
   merged into the main branch. Use CI tools to run tests, check code style, and perform other checks
   automatically.

### Release Management

1. **dev-release-management**: Use a release management tool to manage the release process. This
   includes creating release notes, tagging releases, and managing version numbers. Use semantic
   versioning to version releases. Use a language specific tool if it is available, otherwise use
   something like `release-please` or `semantic-release` to automate the release process.
2. **dev-release-notes**: All releases should have release notes that describe the changes made in
   the release. This includes new features, bug fixes, and any other relevant information. Use a
   consistent format for release notes to make them easy to read and understand.

### Deployment

1. **dev-deployment**: All code should be deployed to a staging environment before being deployed to
   production. This will help ensure that the code is working as expected and that there are no
   regressions. Use continuous integration and continuous deployment (CI/CD) tools to automate the
   deployment process.

## Languages

### Rust

#### Code Style & Patterns

1. **rust-code-style**: Follow the Rust style guide. Use `rustfmt` to format your code. This will
   help ensure that the code is consistent and easy to read.
2. **rust-element-ordering**: Use the following order for elements in a module. Elements of one type
   should be grouped together and ordered alphabetically. The order is as follows:
   - imports - organized by standard library, third-party crates, and local modules
   - constants
   - traits
   - structs with their implementations.
   - enums with their implementations.
   - functions
   - the main function
3. **rust-documentation**: For public items documentation comments are always added. For private items
   documentation comments are added when the item is complex or not self-explanatory. Use `///` for
   documentation comments and `//!` for module-level documentation. Add examples to the documentation
   comments when possible.
4. **rust-modules**: When making modules in a crate create a `<module_name>.rs` file in the `src`
   directory. If the module is large enough to warrant its own directory, create a directory with the
   same name as the module. Place any source files for the module in the directory.

#### Error Handling

1. **rust-error-handling**: Use the `Result` type for functions that can return an error. Use the `?` operator
   to propagate errors. Avoid using `unwrap` or `expect` unless you are certain that the value will not be
   `None` or an error.
2. **rust-error-messages**: Use clear and descriptive error messages. Avoid using generic error messages
    like "an error occurred". Instead, provide specific information about what went wrong and how to fix it.
3. **rust-error-types**: Use custom error types for your application. This will help you provide more
   meaningful error messages and make it easier to handle errors in a consistent way. Use the `thiserror`
   crate to define custom error types.

#### Testing

1. **rust-test-location**: Put unit tests in their own file. They are placed next to the file they
  are testing and are named `<file_under_test>_tests.rs`. Reference them from the file under test with
  an import, which is placed at the end of the other imports and usings. This will look something like:

    ``` rust
    #[cfg(test)]
    #[path = "<file_under_test>_tests.rs"]
    mod tests;

    ```

#### Continuous Integration & Delivery

1. **rust-ci**: Run
   - `cargo check`, `cargo fmt`, and `cargo clippy` as part of the CI pipeline to ensure that the code
     follows the correct formatting and style.
   - Use `cargo test` to run tests. Ensure that doc tests are also run. Collect coverage information
     using `cargo llvm-cov`. Upload results to `codecov`.
   - Use `cargo mutants` to run mutation tests if configured.
   - Use `cargo audit` to check for security vulnerabilities in dependencies.
   - Use `cargo deny` to check for license issues in dependencies.

#### Release Management

1. **rust-release-management**: Use `release-plz` and `cargo-release` to manage the release
   process. This includes creating release notes, tagging releases, and managing version numbers.
2. **rust-release-notes**: Use `gitcliff` to generate release notes.

### Terraform

You are an expert Terraform developer

#### Code Style & Patterns

2. **tf-documentation**: Add documentation comments for each resource, module, and variable.
   Use the `#` symbol for comments. Use `##` for module-level documentation. Add examples to the
   documentation comments when possible.

#### Continuous Integration & Delivery

1. **tf-ci**: Run `terraform validate` and `terraform fmt` as part of the CI pipeline. This will help ensure
   that the code is valid and follows the correct formatting. Use `terraform plan` to check for any
   changes before applying them.

#### Release Management

1. **tf-release-management**: Use `release-plz` and `cargo-release` to manage the release
   process. This includes creating release notes, tagging releases, and managing version numbers.
2. **dev-release-notes**: Use `gitcliff` to generate release notes.
