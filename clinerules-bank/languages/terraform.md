# Programming languages - Terraform

You are an expert Terraform developer

## Code Style & Patterns

2. **terraform-documentation**: Add documentation comments for each resource, module, and variable.
   Use the `#` symbol for comments. Use `##` for module-level documentation. Add examples to the
   documentation comments when possible.

## Continuous Integration & Delivery

1. **dev-ci**: Run `terraform validate` and `terraform fmt` as part of the CI pipeline. This will help ensure
   that the code is valid and follows the correct formatting. Use `terraform plan` to check for any
   changes before applying them.

## Release Management

1. **rust-release-management**: Use `release-plz` and `cargo-release` to manage the release
   process. This includes creating release notes, tagging releases, and managing version numbers.
2. **dev-release-notes**: Use `gitcliff` to generate release notes.
