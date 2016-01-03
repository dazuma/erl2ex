# Changelog

Erl2ex is currently pre-alpha software. Expect significant backwards-incompatible changes for the time being.

## v0.0.3 (????-??-??)

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
