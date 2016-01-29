
defmodule Erl2ex.Parse.Context do

  @moduledoc false

  alias Erl2ex.Parse.Context


  defstruct include_path: [],
            cur_file_path: nil,
            reverse_forms: false,
            auto_export_suffixes: []


  def build(opts) do
    include_path = opts
      |> Keyword.get_values(:include_dir)
      |> Enum.uniq
    %Context{
      include_path: include_path,
      cur_file_path: Keyword.get(opts, :cur_file_path, nil),
      reverse_forms: Keyword.get(opts, :reverse_forms, false),
      auto_export_suffixes: Keyword.get_values(opts, :auto_export_suffix)
    }
  end


  def build_opts_for_include(%Context{include_path: include_path}) do
    include_path
      |> Enum.map(&({:include_dir, &1}))
      |> Keyword.put(:reverse_forms, true)
  end


  def find_file(%Context{include_path: include_path, cur_file_path: cur_file_path}, path) do
    if cur_file_path != nil do
      include_path = [Path.dirname(cur_file_path) | include_path]
    end
    include_path = [File.cwd!() | include_path]
    include_path
      |> Enum.find_value(fn dir ->
        full_path = Path.expand(path, dir)
        if File.regular?(full_path), do: full_path, else: false
      end)
  end


  def cur_file_path_for_display(%Context{cur_file_path: nil}), do:
    "(Unknown source file)"

  def cur_file_path_for_display(%Context{cur_file_path: path}), do:
    path


  def is_auto_exported?(%Context{auto_export_suffixes: suffixes}, name) do
    name |> Atom.to_string |> String.ends_with?(suffixes)
  end

end
