# Prompt instructions

- **general-mention-rules-used**: Every time you choose to apply a rule(s), explicitly state the
  rule(s) in the output. You can use the `rule` tag to do this. For example, `#rule: rule_name`.

- **general-mention-knowledge**: List all assumptions and uncertainties you need to clear up before
  completing this task.

- **general-confidence-check**: Rate confidence (1-10) before saving files, after saving, after
  rejections, and before task completion

- **general-grounding**: Always verify and validate information from multiple sources. Cross-reference findings from
  different tools and document results and sources

## Tooling

- **general-tool-use-os**: Use operating system relevant tools when possible. For example, use
  `bash` on Linux and MacOS, and `powershell` on Windows

- **general-tool-use-file-search**: When searching for files in the workspace make sure to also
  search hidden directories (e.g. `./.github`, `./.vscode`, etc.). But skip the `.git` directory.

- **scm-git-pull-request-title**: The pull request title should follow the conventional commit format.
  `<type>(<scope>): <subject>` where `type` is one of the following: `feat`, `fix`, `chore`, `docs`,
  `style`, `refactor`, `perf`, `test`.

- **scm-git-pull-request-template**: Use the pull request template if there is one. The pull request
  template can be found in the `./.github/PULL_REQUEST_TEMPLATE.md` file.

- **scm-git-pull-request-review**: All pull requests should be reviewed by at least one other developer and
  GitHub copilot before being merged into the main branch.

- **scm-branch-naming**: The branch name should be a brief summary of the changes being made. Branch
  names should be in lowercase and use hyphens to separate words. For example, `fix-bug-in-login-page`
  or `feature-add-new-user`.

- **scm-commit-message**: For commit messages the
  type should be one of the following: `feat`, `fix`, `chore`, `docs`, `style`, `refactor`, `perf`,
  `test`. The scope should be the name of the module or component being changed. The subject should
  be a short description of the change. The `work_item_ref` is one of the following issue references:
  `references` or `related to` followed by the issue number.
  Finally those parts make the following format for commit messages:

  ```text
  type(scope): subject

  description

   <work_item_ref>
  ```

## Workflow Guidelines

- **wf-issue-use**: Before starting any task determine if you need an issue for it. If so search for the
  appropriate issue in the issue tracker. If there is no issue, suggest to create one.

- **wf-find-issue**: When searching for issues
  do an approximate comparison of the issue title and description with the task at hand. If you find multiple
  issues that are an approximate match, ask the user to clarify which issue should be used.

- **wf-issue-template**: When creating an issue use the issue templates. Issue templates can be found in the
  `./.github/ISSUE_TEMPLATE` directory.

- **wf-issue-creation**: All issues should be created in the repository. This includes bugs, new features,
  and any other changes to the codebase. Issues should be created for all tasks, even if they are small.
  Issues should be linked together to show the relationship between them.

- **wf-branch-selection**: Each task is done on its own branch. Before you start a task check that you are on the
  correct branch. Code is *never* directly committed to the `main` or `master` branches. If no
  suitable branch exist create a new local branch from `main` or `master` for your changes and switch to that branch.
  For example `git checkout -b feature-add-new-user main` or `git checkout -b fix-bug-in-login-page master`.

- **wf-design-before-code**: Before writing any code for a new feature or bug fix, create a design document
  that outlines the architecture, data flow, and any other relevant details. Place design documents in the
  `specs` directory of the repository.

- **wf-design-spec-layout**: The design document should be in markdown format and any diagrams should
  should follow the mermaid language. Follow the markdown style guide and ensure that lines are no
  longer than 100 characters. It should follow the following structure:
  - Title
  - Problem description
  - Surrounding context
  - Proposed solution
    - Design goals
    - Design constraints
    - Design decisions
    - Alternatives considered
  - Design
    - Architecture
    - Data flow
    - Other relevant details
  - Conclusion

- **wf-code-tasks**: Coding starts with an implementation issue. During the session we only solve the
  implementation issue. If we find other changes that we want to make, we create new issues for
  them.

- **wf-code-style**: All code should be easy to understand and maintain. Use clear and descriptive
  names for variables, functions, and classes. Always follow the coding standards and best practices
  for the programming language being used.

- **wf-unit-test-coverage**: All business logic should be covered by unit tests. We're aiming to cover
  all input and output paths of the code. This includes edge cases and error handling. Use coverage
  tools to measure the test coverage and use mutation testing to ensure that the tests are
  effective.

- **wf-documentation**: The coding task is not complete without documentation. All code should be
  well-documented. Use comments to explain the purpose of complex code and to provide context for
  future developers. Use docstrings to document functions, classes, and modules. The documentation
  should be clear and concise.

- **wf-documentation-standards**: Follow the documentation standards and best practices for the
  programming language being used.

- **wf-ci**: All changes should be checked with a continuous integration (CI) tool before being
  merged into the main branch. Use CI tools to run tests, check code style, and perform other checks
  automatically.

- **wf-pull-request**: Create a pull request (PR) for all changes made to the codebase.
  The PR should include a description which changes were made, why the changes were made, links to
  relevant issue numbers, results from testing, and any other relevant information. Assign the PR to the
  person who created it. Always invite copilot on the review.

- **wf-release-management**: Use a release management tool to manage the release process. This
  includes creating release notes, tagging releases, and managing version numbers. Use semantic
  versioning to version releases. Use a language specific tool if it is available, otherwise use
  something like `release-please` or `semantic-release` to automate the release process.

- **wf-release-notes**: All releases should have release notes that describe the changes made in
  the release. This includes new features, bug fixes, and any other relevant information. Use a
  consistent format for release notes to make them easy to read and understand.

- **wf-deployment**: All code should be deployed to a staging environment before being deployed to
  production. This will help ensure that the code is working as expected and that there are no
  regressions. Use continuous integration and continuous deployment (CI/CD) tools to automate the
  deployment process.

## Languages

### Markdown

- **md-lines**: Ensure that lines are no longer than 100 characters. Use proper formatting for lists, headings, and code blocks.

### Rust

- **rust-code-style**: Follow the Rust style guide. Use `rustfmt` to format your code. This will
  help ensure that the code is consistent and easy to read.

- **rust-element-ordering**: Use the following order for elements in a module. Elements of one type
  should be grouped together and ordered alphabetically. The order is as follows:
  - imports - organized by standard library, third-party crates, and local modules
  - constants
  - traits
  - structs with their implementations.
  - enums with their implementations.
  - functions
  - the main function

- **rust-documentation**: For public items documentation comments are always added. For private items
  documentation comments are added when the item is complex or not self-explanatory. Use `///` for
  documentation comments and `//!` for module-level documentation. Add examples to the documentation
  comments when possible.

- **rust-modules**: When making modules in a crate create a `<module_name>.rs` file in the `src`
  directory. If the module is large enough to warrant its own directory, create a directory with the
  same name as the module. Place any source files for the module in the directory.

- **rust-error-handling**: Use the `Result` type for functions that can return an error. Use the `?` operator
  to propagate errors. Avoid using `unwrap` or `expect` unless you are certain that the value will not be
  `None` or an error.

- **rust-error-messages**: Use clear and descriptive error messages. Avoid using generic error messages
  like "an error occurred". Instead, provide specific information about what went wrong and how to fix it.

- **rust-error-types**: Use custom error types for your application. This will help you provide more
  meaningful error messages and make it easier to handle errors in a consistent way. Use the `thiserror`
  crate to define custom error types.

- **rust-test-location**: Put unit tests in their own file. They are placed next to the file they
  are testing and are named `<file_under_test>_tests.rs`. Reference them from the file under test with
  an import, which is placed at the end of the other imports and usings. This will look something like:

    ``` rust
    #[cfg(test)]
    #[path = "<file_under_test>_tests.rs"]
    mod tests;
    ```

- **rust-ci**: Run
  - `cargo check`, `cargo fmt`, and `cargo clippy` as part of the CI pipeline to ensure that the code
    follows the correct formatting and style.
  - Use `cargo test` to run tests. Ensure that doc tests are also run. Collect coverage information
    using `cargo llvm-cov`. Upload results to `codecov`.
  - Use `cargo mutants` to run mutation tests if configured.
  - Use `cargo audit` to check for security vulnerabilities in dependencies.
  - Use `cargo deny` to check for license issues in dependencies.

- **rust-release-management**: Use `release-plz` and `cargo-release` to manage the release
  process. This includes creating release notes, tagging releases, and managing version numbers.

- **rust-release-notes**: Use `gitcliff` to generate release notes.

### Terraform

- **tf-documentation**: Add documentation comments for each resource, module, and variable.
  Use the `#` symbol for comments. Use `##` for module-level documentation. Add examples to the
  documentation comments when possible.

- **tf-ci**: Run `terraform validate` and `terraform fmt` as part of the CI pipeline. This will help ensure
  that the code is valid and follows the correct formatting. Use `terraform plan` to check for any
  changes before applying them.

- **tf-release-management**: Use `release-plz` and `cargo-release` to manage the release
  process. This includes creating release notes, tagging releases, and managing version numbers.

- **wf-release-notes**: Use `gitcliff` to generate release notes.

## Project Management

- Source control: Git, remote repository in GitHub
- Issue tracker: GitHub Issues
- CI/CD: GitHub Actions
- Code review: GitHub Pull Requests
- Documentation: Markdown files in the repository
