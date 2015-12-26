# TODO List

This is a (certainly partial) list of known issues and missing capabilities.

## Language

*   Spec with module-qualified function name (P2)

## Preprocessor

*   Support file inclusion (P1)
*   Check that macro defines work with guard fragments. See examples in elixir/src/elixir_tokenizer.erl (P1)
*   Allow defining macros from env variables, e.g. debug (P2)
*   Make sure defined_* attributes are properly initialized (P2)
*   Invoking const macros as functions (P2)
*   Stringifying macro arguments, e.g. ??Arg (P2)

## Suspected limitations in Elixir's language support

*   Record declarations with type info, e.g. -record(foo, {field1 :: integer}). Currently the converter drops the types.
*   Binary expressions with complex or combination size/type specs. Currently the converter crashes.

## Other features, comments, tooling

*   Write tool documentation (P1)
*   Transform doc comments (P1)
*   Handle inline comments (P2)
*   Option to elixirize module names (P2)
*   Nicer error reporting (P2)
