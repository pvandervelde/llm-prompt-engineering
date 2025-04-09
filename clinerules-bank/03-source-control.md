# Source control Guidelines

All rules are to be followed in all projects. The rules are divided into categories for better organization.
Rules in this file are prefixed with `scm-` to indicate that they are source control rules.

## Assumptions

1. Assume that the GitHub CLI is available and signed in

## General

## Branches

1. **scm-create-branch**: Before making any changes to the codebase, check that you are on the
  correct branch. Code is *never* directly committed to the `main` or `master` branches. If no
  suitable branch exist create a new branch for your changes and switch to that branch. If
  you cannot create a branch, notify the user.
2. **scm-branch-naming**: The branch name should be a brief summary of the changes being made. Branch
   names should be in lowercase and use hyphens to separate words. For example, `fix-bug-in-login-page`
   or `feature-add-new-user`.

## Committing

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

## Pull Requests

1. **scm-git-pull-request-content**: Create a pull request (PR) for all changes made to the codebase.
   The PR should include a description which changes were made, why the changes were made, links to
   relevant ssue numbers, results from testing, and any other relevant information. Follow the pull
   request template if there is one.
2. **scm-git-pull-request-review**: All pull requests should be reviewed by at least one other developer
   before being merged into the main branch. Additionally we always invite copilot on the review if
   available.
