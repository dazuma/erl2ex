# TODO List

This is a (certainly partial) list of known issues and missing capabilities.

## Language

*   Support try, catch and throw (P1)
*   Support spec attribute (P1)
*   Support behaviour and callback attributes (P1)
*   Support type info in records (P2)
*   Expand list of known Kernel functions (P2)
*   Support bit/binary expressions with complex size/type specifiers (P3)

## Preprocessor

*   Support file inclusion (P1)
*   Check that macro defines work with guard fragments. See examples in elixir/src/elixir_tokenizer.erl (P1)
*   Allow defining macros from env variables, e.g. debug (P2)
*   Make sure defined_* attributes are properly initialized (P2)
*   Invoking const macros as functions (P2)
*   Stringifying macro arguments, e.g. ??Arg (P2)

## Other features, comments, tooling

*   Write tool documentation (P1)
*   Transform doc comments (P1)
*   Handle inline comments (P2)
*   Option to elixirize module names (P2)
*   Nicer error reporting (P2)
