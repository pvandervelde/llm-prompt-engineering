# Development Guidelines

All rules are to be followed in all projects. The rules are divided into categories for better organization.
Rules in this file are prefixed with `dev-` to indicate that they are development rules.

## Design

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

## Coding

1. **dev-code-tasks**: Coding starts with an implementation issue. During the session we only solve the
   implementation issue. If we find other changes that we want to make, we create new issues for
   them.
2. **dev-code-source-control**: Development of a new issue starts on a new branch. We regularly commit our
   changes to the branch. We use the `git` command line interface (CLI) to commit our changes. Once
   the work is complete, we create a pull request (PR) to merge the changes into the main branch. The PR
   should follow the rules outlines in the source control guidelines.
2. **dev-code-style**: All code should be easy to understand and maintain. Use clear and descriptive
   names for variables, functions, and classes. Always follow the coding standards and best practices
   for the programming language being used.

## Testing standards

1. **dev-unit-test-coverage**: All business logic should be covered by unit tests. We're aiming to cover
   all input and output paths of the code. This includes edge cases and error handling. Use coverage
   tools to measure the test coverage and use mutation testing to ensure that the tests are
   effective.

## Documentation

1. **dev-documentation**: The coding task is not complete without documentation. All code should be
   well-documented. Use comments to explain the purpose of complex code and to provide context for
   future developers. Use docstrings to document functions, classes, and modules. The documentation
   should be clear and concise.
2. **dev-documentation-standards**: Follow the documentation standards and best practices for the
   programming language being used.

## Continuous Integration & Delivery

1. **dev-ci**: All changes should be checked with a continuous integration (CI) tool before being
   merged into the main branch. Use CI tools to run tests, check code style, and perform other checks
   automatically.

## Release Management

1. **dev-release-management**: Use a release management tool to manage the release process. This
   includes creating release notes, tagging releases, and managing version numbers. Use semantic
   versioning to version releases. Use a language specific tool if it is available, otherwise use
   something like `release-please` or `semantic-release` to automate the release process.
2. **dev-release-notes**: All releases should have release notes that describe the changes made in
   the release. This includes new features, bug fixes, and any other relevant information. Use a
   consistent format for release notes to make them easy to read and understand.

## Deployment

1. **dev-deployment**: All code should be deployed to a staging environment before being deployed to
   production. This will help ensure that the code is working as expected and that there are no
   regressions. Use continuous integration and continuous deployment (CI/CD) tools to automate the
   deployment process.
