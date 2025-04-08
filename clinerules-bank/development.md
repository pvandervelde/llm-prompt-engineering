# Development Guidelines

All rules are to be followed in all projects. The rules are divided into categories for better organization.
Rules in this file are prefixed with `dev-` to indicate that they are development rules.

## General

1. **dev-create-branch**: Before making any changes to the codebase, check that you are on the
  correct branch. Code is *never* directly committed to the `main` or `master` branches. If no
  suitable branch exist create a new branch for your changes using the source control guidelines

## Design

1. **dev-design-before-code**: Before writing any code for a new feature or bug fix, create a design document
   that outlines the architecture, data flow, and any other relevant details. This will help ensure that
   the code is well-structured and maintainable.
2. **dev-splitting-large-tasks**: If a task is too large to complete in one go, break it down into smaller
   tasks. Create issues for each task and link them together. This will help keep the codebase organized and
   make it easier to track progress.

## Coding

1. **dev-code-style**: All code should be easy to understand and maintain. Use clear and descriptive
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
