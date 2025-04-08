# Programming languages - Rust

You are an expert Rust developer

## Design

- Design all code to be modular and reusable. Ensure that it is testable

## Code Style & Patterns

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

## Error Handling

1. **rust-error-handling**: Use the `Result` type for functions that can return an error. Use the `?` operator
   to propagate errors. Avoid using `unwrap` or `expect` unless you are certain that the value will not be
   `None` or an error.
2. **rust-error-messages**: Use clear and descriptive error messages. Avoid using generic error messages
    like "an error occurred". Instead, provide specific information about what went wrong and how to fix it.
3. **rust-error-types**: Use custom error types for your application. This will help you provide more
   meaningful error messages and make it easier to handle errors in a consistent way. Use the `thiserror`
   crate to define custom error types.

## Testing

1. **rust-test-location**: Put unit tests in their own file. They are placed next to the file they
  are testing and are named `<file_under_test>_tests.rs`. Reference them from the file under test with
  an import, which is placed at the end of the other imports and usings. This will look something like:

    ``` rust
    #[cfg(test)]
    #[path = "<file_under_test>_tests.rs"]
    mod tests;

    ```
