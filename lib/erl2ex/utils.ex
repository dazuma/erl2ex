
defmodule Erl2ex.Utils do

  @moduledoc false


  def find_available_name(basename, used_names), do:
    find_available_name(to_string(basename), used_names, "", 0)

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


  def lower_str("_"), do: "_"
  def lower_str(<< "_" :: utf8, rest :: binary >>), do:
    << "_" :: utf8, lower_str(rest) :: binary >>
  def lower_str(<< first :: utf8, rest :: binary >>), do:
    << String.downcase(<< first >>) :: binary, rest :: binary >>

  def lower_atom(atom), do:
    atom |> Atom.to_string |> lower_str |> String.to_atom


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

end
