
defmodule Erl2ex.Cli do

  def main(argv) do
    {options, args, errors} =
      OptionParser.parse(argv,
        strict: [
          output: :string,
          verbose: :boolean,
          help: :boolean
        ],
        aliases: [
          v: :verbose,
          "?": :help,
          o: :output
        ]
      )

    case Keyword.get_values(options, :verbose) |> Enum.count do
      0 -> Logger.configure(level: :warn)
      1 -> Logger.configure(level: :info)
      _ -> Logger.configure(level: :debug)
    end

    cond do
      not Enum.empty?(errors) ->
        display_errors(errors)
      Keyword.get(options, :help) ->
        display_help
      true ->
        run_conversion(args, options)
    end
  end


  defp run_conversion([], options) do
    IO.read(:all)
      |> Erl2ex.convert_str(options)
      |> IO.write
  end

  defp run_conversion([path], options) do
    output = Keyword.get(options, :output)
    cond do
      File.dir?(path) ->
        Erl2ex.convert_dir(path, output, options)
      File.regular?(path) ->
        Erl2ex.convert_file(path, output, options)
      true ->
        IO.puts(:stderr, "Could not find input: #{path}")
        System.halt(1)
    end
  end

  defp run_conversion(paths, _) do
    IO.puts(:stderr, "Got too many input paths: #{inspect(paths)}\n")
    display_help
    System.halt(1)
  end


  defp display_errors(errors) do
    Enum.each(errors, fn
      {switch, val} ->
        IO.puts(:stderr, "Unrecognized switch: #{switch} #{val}")
      end)
    IO.puts(:stderr, "")
    display_help
    System.halt(1)
  end


  defp display_help do
    IO.write :stderr, """
      Usage: erl2ex [options] [input path]

        --output, -o "path"  Set the output file or directory path
        --verbose, -v        Display verbose status
        --help, -?           Display help text

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

end
