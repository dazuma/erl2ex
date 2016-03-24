# Main entry points for erl2ex.

defmodule Erl2ex do

  @moduledoc """
  Erl2ex is an Erlang to Elixir transpiler, converting well-formed Erlang
  source to Elixir source with equivalent functionality.

  The goal is to produce correct, functioning Elixir code, but not necessarily
  perfectly idiomatic. This tool may be used as a starting point when porting
  code from Erlang to Elixir, but manual cleanup will likely be desired.

  This module provides the main entry points into Erl2ex.
  """

  alias Erl2ex.Results
  alias Erl2ex.Sink
  alias Erl2ex.Source

  alias Erl2ex.Pipeline.Analyze
  alias Erl2ex.Pipeline.Codegen
  alias Erl2ex.Pipeline.Convert
  alias Erl2ex.Pipeline.InlineIncludes
  alias Erl2ex.Pipeline.Parse


  @typedoc """
  Options that may be provided to a conversion run.

  Recognized options are:
  *   `:include_dir` Add a directory to the include path.
  *   `:define_prefix` Prefix added to the environment variable or config key
      names that are read to initialize macro definitions. Default: "DEFINE_".
  *   `:defines_from_config` An application whose config should be used to
      initialize macro definitions. If not specified or set to nil, system
      environment variables will be used.
  *   `:emit_file_headers` Add a header comment to each file. Default is true.
  *   `:verbosity` Set the output verbosity level. (Default is 0, which
      outputs only error messages. 1 outputs basic status information, and
      2 outputs debug information.)
  """
  @type options :: [
    include_dir: Path.t,
    define_prefix: String.t,
    defines_from_config: atom,
    emit_file_headers: boolean,
    verbosity: integer
  ]


  @typedoc """
  A file identifier, which may be a filesystem path or a symbolic id.
  """

  @type file_id :: Path.t | atom


  @doc """
  Converts the source for an Erlang module, represented as a string.

  If the conversion is successful, returns a tuple of {:ok, result}.
  If an error occurs, returns a tuple of {:error, error_details}.
  """

  @spec convert_str(String.t, options) ::
    {:ok, String.t} | {:error, %CompileError{}}

  def convert_str(source_str, opts \\ []) do
    internal_convert_str(source_str, opts,
      fn(results, sink) ->
        case Results.get_error(results) do
          nil -> Sink.get_string(sink, nil)
          err -> {:error, err}
        end
      end)
  end


  @doc """
  Converts the source for an Erlang module, represented as a string, and
  returns the Elixir source as a string.

  Raises a CompileError if an error occurs.
  """

  @spec convert_str!(String.t, options) :: String.t

  def convert_str!(source_str, opts \\ []) do
    internal_convert_str(source_str, opts,
      fn(results, sink) ->
        Results.throw_error(results)
        {:ok, str} = Sink.get_string(sink, nil)
        str
      end)
  end


  defp internal_convert_str(source_str, opts, result_handler) do
    opts = Keyword.merge(opts, source_data: source_str)
    source = Source.start_link(opts)
    sink = Sink.start_link(allow_get: true)
    results_collector = Results.Collector.start_link()
    try do
      convert(source, sink, results_collector, nil, nil, opts)
      results = Results.Collector.get(results_collector)
      result_handler.(results, sink)
    after
      Source.stop(source)
      Sink.stop(sink)
      Results.Collector.stop(results_collector)
    end
  end


  @doc """
  Converts a single Erlang source file, and writes the generated Elixir code
  to a new file.

  You must provide the relative or absolute path to the Erlang source. You may
  optionally provide a path to the Elixir destination. If the destination is
  not specified, the result will be written in the same directory as the source.

  Returns a results object.
  """

  @spec convert_file(Path.t, Path.t | nil, options) :: Results.t

  def convert_file(source_path, dest_path \\ nil, opts \\ []) do
    if dest_path == nil do
      dest_path = "#{Path.rootname(source_path)}.ex"
    end
    cur_dir = File.cwd!
    include_dirs = Keyword.get_values(opts, :include_dir)
    source = Source.start_link(source_dir: cur_dir, include_dirs: include_dirs)
    sink = Sink.start_link(dest_dir: cur_dir)
    results_collector = Results.Collector.start_link()
    try do
      convert(source, sink, source_path, dest_path, opts)
      if Keyword.get(opts, :verbosity, 0) > 0 do
        IO.puts(:stderr, "Converted #{source_path} -> #{dest_path}")
      end
      Results.Collector.get(results_collector)
    after
      Source.stop(source)
      Sink.stop(sink)
      Results.Collector.stop(results_collector)
    end
  end


  @doc """
  Searches a directory for Erlang source files, and writes corresponding
  Elixir files for each module.

  By default, the Elixir files will be written in the same directories as the
  Erlang source files. You may optionally provide a different base directory
  for the destination files.

  Returns a results object.
  """

  @spec convert_dir(Path.t, Path.t | nil, options) :: Results.t

  def convert_dir(source_dir, dest_dir \\ nil, opts \\ []) do
    if dest_dir == nil do
      dest_dir = source_dir
    end
    source = opts
      |> Keyword.put(:source_dir, source_dir)
      |> Source.start_link
    sink = Sink.start_link(dest_dir: dest_dir)
    results_collector = Results.Collector.start_link()
    try do
      "#{source_dir}/**/*.erl"
        |> Path.wildcard
        |> Enum.each(fn source_full_path ->
          source_rel_path = Path.relative_to(source_full_path, source_dir)
          dest_rel_path = "#{Path.rootname(source_rel_path)}.ex"
          dest_full_path = Path.join(dest_dir, dest_rel_path)
          convert(source, sink, results_collector, source_rel_path, dest_rel_path, opts)
          if Keyword.get(opts, :verbosity, 0) > 0 do
            IO.puts(:stderr, "Converted #{source_full_path} -> #{dest_full_path}")
          end
        end)
      Results.Collector.get(results_collector)
    after
      Source.stop(source)
      Sink.stop(sink)
      Results.Collector.stop(results_collector)
    end
  end


  @doc """
  Given a source and a sink, and the source path for one Erlang source file,
  converts to Elixir and writes the result to the sink at the given destination
  path. Writes the result to the given results collector. Returns :ok.
  """

  @spec convert(Source.t, Sink.t, Results.Collector.t, Erl2ex.file_id, Erl2ex.file_id, options) :: :ok

  def convert(source, sink, results_collector, source_path, dest_path, opts \\ []) do
    {source_str, actual_source_path} = Source.read_source(source, source_path)
    if actual_source_path != nil do
      opts = [{:cur_file_path, actual_source_path} | opts]
    end
    try do
      str = source_str
        |> Parse.string(opts)
        |> InlineIncludes.process(source, actual_source_path)
        |> Analyze.forms(opts)
        |> Convert.module(opts)
        |> Codegen.to_str(opts)
      :ok = Sink.write(sink, dest_path, str)
      :ok = Results.Collector.put_success(results_collector, source_path, dest_path)
    rescue
      error in CompileError ->
        :ok = Results.Collector.put_error(results_collector, source_path, error)
    end
    :ok
  end

end
