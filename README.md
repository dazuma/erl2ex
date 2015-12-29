# Erl2ex

[![Build Status](https://travis-ci.org/dazuma/erl2ex.svg?branch=master)](https://travis-ci.org/dazuma/erl2ex)

An Erlang to Elixir transpiler. Converts Erlang source code to equivalent Elixir source.

This software is currently highly experimental. Some capabilities are not yet complete, and so far it has been tested only on small code fragments. See also the Caveats section for a list of known issues and incomplete features.

The vision and end goal is automated conversion of major Erlang code bases (such as potentially Elixir itself) to correct and functional (though not necessarily fully idiomatic) Elixir. It could be used as the first step in doing a port.

## Installing

Erl2ex may be run as a mix task or as a standalone escript.

### Requirements

Erl2ex recognizes Erlang source that is compatible with Erlang 18.x. The generated Elixir source currently requires Elixir 1.1, but in the near future it will require Elixir 1.2.

The Erl2ex tool itself currently requires Elixir 1.1 or later, but in the near future it will require Elixir 1.2.

### Installing the mix task

To run the mix task, first add Erl2ex as a dependency to your existing Elixir project:

```elixir
def deps do
  [ {:erl2ex, ">= 0.0.1", only: :dev} ]
end
```

After adding Erl2ex as a dependency, run `mix deps.get` followed by `mix deps.compile` to install it. An `erl2ex` will now be available. Run `mix help erl2ex` for help.

### Building the escript

To build a standalone command line application (escript), clone this repository using `git clone https://github.com/dazuma/erl2ex.git`, and then run `mix escript.build` within the cloned project.

## Usage

Erl2ex may be run in three modes:

*   It can read an Erlang source file on stdin, and write the generated Elixir source to stdout.
*   It can read a specified Erlang source file (.erl) from the file system, and write the generated Elixir source file (.ex) to the same or a different specified directory.
*   It can search a directory for all Erlang source files (.erl), and write corresponding Elixir source files (.ex) to the same or a different specified directory.

Various switches may also be provided on the command line, including the include path for searching for Erlang include files (.hrl), and other conversion settings.

For detailed help, use `mix help erl2ex` for the mix task, or `erl2ex --help` for the standalone tool.

## Caveats

This software is still under heavy development, and many capabilities are not yet complete. The following is a partial list of known issues and planned features.

### Known issues

*   Macro defines do not work with guard fragments, e.g. expressions delimited by commas or semicolons. See examples in https://github.com/elixir-lang/elixir/blob/master/lib/elixir/src/elixir_tokenizer.erl.
*   Some "defined_*" attributes (used for macro-based flow control) are not initialized properly.
*   Invoking constant macros as function names is not working. e.g. if `-define(A, m:f).`, it should be legal to invoke `?A()`.
*   Errors during parsing typically get reported as almost completely incomprehensible pattern match errors out of the bowels of the converter.
*   Record declarations with type info (e.g. `-record(foo, {field1 :: integer}).`) are not supported. Currently the converter drops the types. This seems to be a limitation of Elixir itself.
*   Binary expressions with complex or combination size/type specs are not supported, and cause the converter to crash. An example is `<<1:16/integer-signed-native>>`. This also seems to be a limitation of Elixir itself.

### Desired features

*   Generate exdoc comments, probably based on heuristics the funtion comments.
*   Do something reasonable with inline comments.
*   Provide an option to elixirize module names (e.g. instead of generating `defmodule :my_erlang_module`, generate `defmodule MyErlangModule`)
*   Provide (possibly optional) translation of include files (.hrl) to separate modules rather than copying into the including module, so the declarations can be shared after translation to Elixir.
*   Provide the ability to define constants from the environment, similar to -D for other languages. Elixir doesn't have a preprocessor, but we might do this using environment variables and/or config.

## Contributing

While we appreciate contributions, please note that this software is currently highly experimental, and the code is evolving very rapidly. It is recommended to contact the author before embarking on a major pull request. More detailed contribution guidelines will be provided when the software stabilizes further.

The source can be found on Github at [https://github.com/dazuma/erl2ex](https://github.com/dazuma/erl2ex)

## License

Copyright 2015 Daniel Azuma

This software is licensed under a BSD style license.

See the LICENSE.md file for more information.
