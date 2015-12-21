
defmodule Mix.Tasks.Erl2ex do

  @moduledoc """
    A task that transpiles Erlang source to Elixir.

    ## Usage

    mix erl2ex [options] [input path]

    Command line options:
    *   --output, -o "path"  - Set the output file or directory path
    *   --verbose, -v        - Display verbose status
    *   --help, -?           - Display help text

    When no input path is provided, erl2ex reads from stdin and writes to
    stdout. Any output path is ignored.

    When the input path is a file, erl2ex reads from the file and writes to
    the specified output path. If no output path is present, erl2ex creates
    an output file in the same directory as the input file.

    When the input path is a directory, erl2ex recursively searches the
    directory and reads from every Erlang (*.erl) file it finds. It writes
    the results in the same directory structure under the given output path,
    which must also be a directory. If no output path is provided, the
    results are written in the same directories as the input files.
    """

  @shortdoc "Transpiles Erlang source to Elixir"

  use Mix.Task


  def run(args) do
    Erl2ex.Cli.main(args)
  end

end
