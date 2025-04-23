# Roo Instructions - ask

## prompt-instructions

**general-mention-rules-used:** Every time you choose to apply a rule(s), explicitly state the
rule(s) in the output. You can use the `rule` tag to do this. For example, `#rule: rule_name`.

**general-mention-knowledge:** List all assumptions and uncertainties you need to clear up before
completing this task.

**general-confidence-check:** Rate confidence (1-10) before saving files, after saving, after
rejections, and before task completion

**general-grounding:** Always verify and validate information from multiple sources. Cross-reference findings from
different tools and document results and sources

## tooling

**general-tool-use-os:** Use operating system relevant tools when possible. For example, use
`bash` on Linux and MacOS, and `powershell` on Windows

**general-tool-use-file-search:** When searching for files in the workspace make sure to also
search hidden directories (e.g. `./.github`, `./.vscode`, etc.). But skip the `.git` directory.

## scm

**scm-git-pull-request-review:** All pull requests should be reviewed by at least one other developer and
GitHub copilot before being merged into the main branch.

## workflow-guidelines

**wf-issue-use:** Before starting any task determine if you need an issue for it. If so search for the
appropriate issue in the issue tracker. If there is no issue, suggest to create one.

**wf-find-issue:** When searching for issues
do an approximate comparison of the issue title and description with the task at hand. If you find multiple
issues that are an approximate match, ask the user to clarify which issue should be used.

**wf-documentation:** The coding task is not complete without documentation. All code should be
well-documented. Use comments to explain the purpose of complex code and to provide context for
future developers. Use docstrings to document functions, classes, and modules. The documentation
should be clear and concise.

**wf-documentation-standards:** Follow the documentation standards and best practices for the
programming language being used.

## coding-markdown

**md-lines:** Ensure that lines in markdown are no longer than 100 characters. Use proper formatting for lists, headings, and code blocks.

## coding-rust

**rust-documentation:** For public items documentation comments are always added. For private items
documentation comments are added when the item is complex or not self-explanatory. Use `///` for
documentation comments and `//!` for module-level documentation. Add examples to the documentation
comments when possible.

## coding-terraform

**tf-documentation:** Add documentation comments for each resource, module, and variable.
Use the `#` symbol for comments. Use `##` for module-level documentation. Add examples to the
documentation comments when possible.


