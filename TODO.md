# TODO List

This is a (certainly partial) list of language features remaining to be implemented.

## Syntax/expressions/preprocessor/etc.

*   Expand list of Kernel functions
*   Bit/binary expressions with complex size/type specifiers
*   Try, catch and throw
*   Escape string interpolation syntax and check escape sequences for support
*   behaviour and callback attributes
*   Allow defining macros from env variables (e.g. debug)
*   Make sure defined_* attributes are properly initialized
*   spec attributes
*   Support type info in records
*   File inclusion
*   Invoking const macros as functions
*   Stringifying macro arguments (e.g. ??Arg)
*   Register module attributes
*   Check that macro defines work with guard fragments (examples in elixir/src/elixir_tokenizer.erl)

## Other features, comments, tooling

*   Transform doc comments
*   Handle inline comments
*   Option to elixirize module names
*   Nicer error reporting
