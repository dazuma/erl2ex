
defmodule Erl2ex.Convert.Utils do

  @moduledoc false

  def find_available_name(basename, used_names, prefix), do:
    find_available_name(to_string(basename), used_names, prefix, 1)

  def find_available_name(basename, used_names, prefix, val) do
    suggestion = suggest_name(basename, prefix, val)
    if Set.member?(used_names, suggestion) do
      find_available_name(basename, used_names, prefix, val + 1)
    else
      suggestion
    end
  end

  defp suggest_name(basename, _, 0), do:
    String.to_atom(basename)
  defp suggest_name(basename, prefix, 1), do:
    String.to_atom("#{prefix}_#{basename}")
  defp suggest_name(basename, prefix, val), do:
    String.to_atom("#{prefix}#{val}_#{basename}")


  def lower_str("_"), do: "_"
  def lower_str(<< "_" :: utf8, rest :: binary >>), do:
    << "_" :: utf8, lower_str(rest) :: binary >>
  def lower_str(<< first :: utf8, rest :: binary >>), do:
    << String.downcase(<< first >>) :: binary, rest :: binary >>

  def lower_atom(atom), do:
    atom |> Atom.to_string |> lower_str |> String.to_atom


  def handle_error(context, expr, ast_context \\ nil) do
    line = if is_tuple(expr) and tuple_size(expr) >= 3, do: elem(expr, 1), else: :unknown
    ast_context = if ast_context, do: " #{ast_context}", else: ""
    raise SyntaxError,
      file: Context.cur_file_path_for_display(context),
      line: line,
      description: "Unrecognized Erlang expression#{ast_context}: #{inspect(expr)}"
  end

end
