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

  alias Erl2ex.Parse
  alias Erl2ex.Convert
  alias Erl2ex.Codegen


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
  Information on an error that happened converting a piece of Erlang source.

  The three tuple elements are: the path to the Erlang source file, the line
  number (or `:unknown` if it could not be determined), and a text description
  of the problem (which usually contains some token or AST information.)
  """
  @type source_error :: {Path.t, integer | :unknown, String.t}


  @doc """
  Converts the source for an Erlang module, represented as a string.

  If the conversion is successful, returns a tuple of {:ok, result}.
  If an error occurs, returns a tuple of {:error, error_details}.
  """

  @spec convert_str(String.t, options) ::
    {:ok, String.t} | {:error, source_error}

  def convert_str(source, opts \\ []) do
    try do
      {:ok, convert_str!(source, opts)}
    rescue
      e in CompileError ->
        {:error, {e.file, e.line, e.description}}
    end
  end


  @doc """
  Converts the source for an Erlang module, represented as a string, and
  returns the Elixir source as a string.

  Raises a CompileError if an error occurs.
  """

  @spec convert_str!(String.t, options) :: String.t

  def convert_str!(source, opts \\ []) do
    source
      |> Parse.from_str(opts)
      |> Convert.module(opts)
      |> Codegen.to_str(opts)
  end


  @doc """
  Converts a single Erlang source file, and writes the generated Elixir code
  to a new file.

  You must provide the relative or absolute path to the Erlang source. You may
  optionally provide a path to the Elixir destination. If the destination is
  not specified, the result will be written in the same directory as the source.

  If the conversion is successful, returns a tuple of {:ok, path} where "path"
  is the path to the generated Elixir file.
  If an error occurs, returns a tuple of {:error, error_details}.
  """

  @spec convert_file(Path.t, Path.t, options) ::
    {:ok, Path.t} | {:error, source_error}

  def convert_file(source_path, dest_path \\ nil, opts \\ []) do
    try do
      {:ok, convert_file!(source_path, dest_path, opts)}
    rescue
      e in CompileError ->
        {:error, {e.file, e.line, e.description}}
    end
  end


  @doc """
  Converts a single Erlang source file, and writes the generated Elixir code
  to a new file.

  You must provide the relative or absolute path to the Erlang source. You may
  optionally provide a path to the Elixir destination. If the destination is
  not specified, the result will be written in the same directory as the source.

  Returns the path to the generated Elixir file.
  Raises a CompileError if an error occurs.
  """

  @spec convert_file!(Path.t, Path.t, options) :: Path.t

  def convert_file!(source_path, dest_path \\ nil, opts \\ []) do
    if dest_path == nil do
      dest_path = "#{Path.rootname(source_path)}.ex"
    end
    source_path
      |> Parse.from_file(opts)
      |> Convert.module([{:cur_file_path, source_path} | opts])
      |> Codegen.to_file(dest_path, opts)
    if Keyword.get(opts, :verbosity, 0) > 0 do
      IO.puts(:stderr, "Converted #{source_path} -> #{dest_path}")
    end
    dest_path
  end


  @doc """
  Searches a directory for Erlang source files, and writes corresponding
  Elixir files for each module.

  By default, the Elixir files will be written in the same directories as the
  Erlang source files. You may optionally provide a different base directory
  for the destination files.

  If the conversion is successful, returns a tuple of {:ok, map} where the map
  is from the Erlang source paths to the Elixir destination paths.
  If an error occurs, returns a tuple of {:error, error_details}.
  """

  @spec convert_dir(Path.t, Path.t, options) ::
    {:ok, %{Path.t => Path.t}} | {:error, source_error}

  def convert_dir(source_dir, dest_dir \\ nil, opts \\ []) do
    try do
      {:ok, convert_dir!(source_dir, dest_dir, opts)}
    rescue
      e in CompileError ->
        {:error, {e.file, e.line, e.description}}
    end
  end


  @doc """
  Searches a directory for Erlang source files, and writes corresponding
  Elixir files for each module.

  By default, the Elixir files will be written in the same directories as the
  Erlang source files. You may optionally provide a different base directory
  for the destination files.

  Returns a map from the Erlang source paths to the Elixir destination paths.
  Raises a CompileError if an error occurs.
  """

  @spec convert_dir!(Path.t, Path.t, options) :: %{Path.t => Path.t}

  def convert_dir!(source_dir, dest_dir \\ nil, opts \\ []) do
    if dest_dir == nil do
      dest_dir = source_dir
    end
    "#{source_dir}/**/*.erl"
      |> Path.wildcard
      |> Enum.map(fn source_path ->
        dest_path = Path.relative_to(source_path, source_dir)
        dest_path = Path.join(dest_dir, dest_path)
        dest_path = "#{Path.rootname(dest_path)}.ex"
        {source_path, convert_file!(source_path, dest_path, opts)}
      end)
      |> Enum.into(%{})
  end

end
