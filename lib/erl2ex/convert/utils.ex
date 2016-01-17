
defmodule Erl2ex.Convert.Utils do

  @moduledoc false


  alias Erl2ex.Convert.Context


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
  defp suggest_name(basename, "", val), do:
    String.to_atom("#{basename}#{val + 1}")
  defp suggest_name(<< "_" :: utf8, basename :: binary >>, prefix, 1), do:
    String.to_atom("_#{prefix}_#{basename}")
  defp suggest_name(basename, prefix, 1), do:
    String.to_atom("#{prefix}_#{basename}")
  defp suggest_name(<< "_" :: utf8, basename :: binary >>, prefix, val), do:
    String.to_atom("_#{prefix}#{val}_#{basename}")
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
    ast_context = if ast_context, do: " #{ast_context}", else: ""
    raise CompileError,
      file: Context.cur_file_path_for_display(context),
      line: find_error_line(expr),
      description: "Unrecognized Erlang expression#{ast_context}: #{inspect(expr)}"
  end

  defp find_error_line(expr) when is_tuple(expr) and tuple_size(expr) >= 3, do: elem(expr, 1)
  defp find_error_line([expr | _]), do: find_error_line(expr)
  defp find_error_line(_), do: :unknown

end
