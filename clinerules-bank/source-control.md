# Source control Guidelines

All rules are to be followed in all projects. The rules are divided into categories for better organization.
Rules in this file are prefixed with `scm-` to indicate that they are source control rules.

## Assumptions

1. Assume that the GitHub CLI is available and signed in

## General

1. **scm-branch-naming**: The branch name should be a brief summary of the changes being made. Branch
   names should be in lowercase and use hyphens to separate words. For example, `fix-bug-in-login-page`
   or `feature/add-new-user`.
2. **scm-staging**: Before committing any code, ensure that all changes are staged and ready to be committed.
   Use `git add .` to stage all changes.
3. **commit-message**: Use the following format for commit messages: `type(scope): subject`. The
   type should be one of the following: `feat`, `fix`, `chore`, `docs`, `style`, `refactor`, `perf`,
   `test`. The scope should be the name of the module or component being changed. The subject should
   be a short description of the change.

## Git
