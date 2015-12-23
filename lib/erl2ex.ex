defmodule Erl2ex do

  @moduledoc """
  Erl2ex is an Erlang to Elixir transpiler, converting well-formed Erlang
  source to Elixir source with equivalent functionality.

  The goal is to produce correct, functioning Elixir code, but not necessarily
  perfectly idiomatic. This tool may be used as a starting point when porting
  code from Erlang to Elixir, but manual cleanup will likely be desired.

  This module provides the main entry points into Erl2ex.
  """

  require Logger


  @type options :: list

  @type result :: :ok | :error


  @doc """
  Converts the source for an Erlang module, represented as a string, and
  returns the Elixir source as a string.
  """

  @spec convert_str(String.t, options) :: String.t

  def convert_str(source, opts \\ []) do
    source
      |> Erl2ex.ErlParse.from_str(opts)
      |> Erl2ex.Convert.module(opts)
      |> Erl2ex.ExWrite.to_str(opts)
  end


  @doc """
  Converts an Erlang source file, and writes the Elixir source to a new file.

  You must provide the relative or absolute path to the Erlang source. You may
  optionally provide a path to the Elixir destination. If the destination is
  not specified, the result will be written in the same directory as the source.
  """

  @spec convert_file(Path.t, Path.t, options) :: result

  def convert_file(source_path, dest_path \\ nil, opts \\ []) do
    if dest_path == nil do
      dest_path = "#{Path.rootname(source_path)}.ex"
    end
    source_path
      |> Erl2ex.ErlParse.from_file(opts)
      |> Erl2ex.Convert.module(opts)
      |> Erl2ex.ExWrite.to_file(dest_path, opts)
    Logger.info("Converted #{source_path} -> #{dest_path}")
    :ok
  end


  @doc """
  Searches a directory for Erlang source files, and writes Elixir soure files
  for each module.
  """

  @spec convert_dir(Path.t, Path.t, options) :: result

  def convert_dir(source_dir, dest_dir \\ nil, opts \\ []) do
    if dest_dir == nil do
      dest_dir = source_dir
    end
    "#{source_dir}/**/*.erl"
      |> Path.wildcard
      |> Enum.each(fn source_path ->
        dest_path = Path.relative_to(source_path, source_dir)
        dest_path = Path.join(dest_dir, dest_path)
        dest_path = "#{Path.rootname(dest_path)}.ex"
        convert_file(source_path, dest_path, opts)
      end)
    :ok
  end

end
