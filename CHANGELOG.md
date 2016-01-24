# Changelog

Erl2ex is currently pre-alpha software. Expect significant backwards-incompatible changes for the time being.

## v0.0.7 (2016-01-25)

*   Overhauled the logic that reconciled imported vs defined functions, and fixed some related issues. Calls of functions with conflicting names are now properly qualified.
*   Allow definition and calling of exported functions with names that the parser won't normally accept; e.g. Elixir keywords such as "do", or names with strange characters such as "E=mc^2".
*   Support invoking a constant macro as a function name.
*   If a function's argument pattern looks like a keyword block, it tried to codegen as such. Fixed.
*   If an Erlang variable name was a capitalized version of an Elixir keyword (such as "End"), it would generate uncompilable Elixir code. Fixed.
*   If the input did not end with a newline, the final form was dropped. Fixed.
*   The "??" stringification preprocessor syntax generated binaries rather than char lists. Fixed.
*   Created a mechanism to compile and run the generated code in unit tests, and started modifying a subset of the tests to use it.
*   Started some optional end-to-end tests that convert and run against common Erlang libraries.
*   Refactor: Break analysis out into a separate stage instead of combining with conversion context.

## v0.0.6 (2016-01-19)

*   Unicode characters greater than 127 were incorrectly encoded in output files, and codepoints greater than 255 caused codegen to crash. Fixed.
*   Convert string() and nonempty_string() Erlang types to the preferred Elixir equivalents, to avoid an Elixir warning.
*   Support for environment variable interpolation in include paths.
*   Support for redefining macros.
*   Support for macro definitions that include comma and semicolon delimited expressions.
*   Generate macros for record_info calls and record index expressions.
*   Erlang characters (e.g. $A) are translated into the Elixir equivalent syntax (e.g. ?A) rather than integers.

## v0.0.5 (2016-01-11)

*   All Erlang macros now translate to Elixir macros, since it seems to be possible for parameterless macros not to be simple values.
*   Variable names could clash with a BIF referenced in another function. Fixed.

## v0.0.4 (2016-01-05)

*   Generate file comments by default.
*   When a comment begins with multiple percent signs, convert all of them to hashes.
*   Separate clauses within a case, receive, or catch leaked variable scopes to each other. Fixed.
*   Support remote function calls with an expression as the function name.
*   Evaluate record_info calls directly since creating a function doesn't seem to work.
*   Ensure "defined_*" attributes are initialized if the erlang source doesn't define them explicitly.
*   Allow definition of constant macros from environment variables or application configs.

## v0.0.3 (2016-01-03)

*   Requires Elixir 1.2. Updated the source for 1.2 warnings and deprecations.
*   Updated and cleaned up ExDoc documentation.
*   Support include_lib directive.
*   Generate comments around each inline included file.
*   Repeated matches on the same variable weren't properly annotated with a caret. Fixed.
*   Funs with no parameters incorrectly translated to a single nil parameter. Fixed.
*   Variable name mangling did not preserve leading underscores. Fixed.

## v0.0.2 (2015-12-31)

*   Better reporting of parse and conversion errors.
*   Support for custom and remote types.
*   Support for the after-clause of receive.
*   Ifdef/ifndef/undef didn't handle capitalized macro names. Fixed.
*   Catch assumed the kind was an atom and didn't accept an expression. Fixed.
*   Recognize bitstring elements with an explicit value, explicit size, and binary type.

## v0.0.1 (2015-12-28)

*   Initial release to hex.
