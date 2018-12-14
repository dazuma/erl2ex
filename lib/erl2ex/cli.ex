# CLI implementation for erl2ex

defmodule Erl2ex.Cli do

  @moduledoc """
  This module provides the command line interface for the erl2ex binary and
  the mix erl2ex task.
  """


  alias Erl2ex.Results


  @doc """
  Runs the erl2ex binary, given a set of command line arguments.
  Returns the OS result code, which is 0 for success or nonzero for failure.
  """

  @spec run([String.t]) :: non_neg_integer

  def run(argv) do
    {options, args, errors} =
      OptionParser.parse(argv,
        strict: [
          output: :string,
          include_dir: [:string, :keep],
          lib_dir: [:string, :keep],
          emit_file_headers: :boolean,
          define_prefix: :string,
          defines_from_config: :string,
          verbose: [:boolean, :keep],
          help: :boolean
        ],
        aliases: [
          v: :verbose,
          "?": :help,
          o: :output,
          "I": :include_dir
        ]
      )

    {options, errors2} = decode_options(options)
    errors = errors ++ errors2

    cond do
      not Enum.empty?(errors) ->
        display_errors(errors)
      Keyword.get(options, :help) ->
        display_help()
      true ->
        run_conversion(args, options)
    end
  end


  @doc """
  Runs the erl2ex binary, given a set of command line arguments.
  Does not return. Instead, halts the VM on completion with the appropriate
  OS result code.
  """

  @spec main([String.t]) :: no_return

  def main(argv) do
    argv
      |> run
      |> System.halt
  end


  @doc """
  Returns the usage documentation for the command line.

  The argument specifies how to invoke the binary (e.g. "erl2ex" or
  "mix erl2ex"). The returned text is in markdown form, but may be rendered
  as plain text as well.
  """

  @spec usage_text(String.t) :: String.t

  def usage_text(invocation \\ "erl2ex") do
    """
    Usage: `#{invocation} [options] [input path]`

    Command line options:
        --output, -o "path"          (Set the output file or directory path)
        --include-dir, -I "dir"      (Add a directory to the include path)
        --[no-]emit-file-headers     (Emit a header comment in each file)
        --define-prefix "prefix"     (Prefix for variables used to define macros)
        --defines-from-config "app"  (Define macros from this application's config)
        --verbose, -v                (Display verbose status)
        --help, -?                   (Display help text)

    erl2ex is a Erlang to Elixir transpiler.

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
  end


  defp decode_options(options) do
    verbose_count = options
      |> Keyword.get_values(:verbose)
      |> Enum.count
    {lib_dirs, errors} = options
      |> Keyword.get_values(:lib_dir)
      |> Enum.reduce({%{}, []}, fn (str, {map, errs}) ->
        case Regex.run(~r{^([^=]+)=([^=]+)$}, str) do
          nil ->
            {map, [{:lib_dir, str} | errs]}
          [_, key, val] ->
            {Map.put(map, String.to_atom(key), val), errs}
        end
      end)

    options = options
      |> Keyword.put(:verbosity, verbose_count)
      |> Keyword.put(:lib_dir, lib_dirs)
    {options, errors}
  end


  defp run_conversion([], options) do
    :all
      |> IO.read
      |> Erl2ex.convert_str!(options)
      |> IO.write
    0
  end

  defp run_conversion([path], options) do
    output = Keyword.get(options, :output)
    cond do
      File.dir?(path) ->
        result = Erl2ex.convert_dir(path, output, options)
        handle_result(result)
      File.regular?(path) ->
        result = Erl2ex.convert_file(path, output, options)
        handle_result(result)
      true ->
        IO.puts(:stderr, "Could not find input: #{path}")
        1
    end
  end

  defp run_conversion(paths, _) do
    IO.puts(:stderr, "Got too many input paths: #{inspect(paths)}\n")
    display_help()
    1
  end


  defp handle_result(results) do
    error = Results.get_error(results)
    if error == nil do
      0
    else
      IO.puts(:stderr, "Error converting #{error.file}, line #{error.line}: #{error.description}")
      1
    end
  end


  defp display_errors(errors) do
    Enum.each(errors, fn
      {switch, val} ->
        IO.puts(:stderr, "Unrecognized or malformed switch: #{switch}=#{val}")
      end)
    IO.puts(:stderr, "")
    display_help()
    1
  end


  defp display_help do
    IO.write(:stderr, usage_text("erl2ex"))
  end

end
