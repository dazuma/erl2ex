# A set of internal utility functions.

defmodule Erl2ex.Pipeline.Utils do

  @moduledoc false


  # Generates a name given a suggested "base" name, and a set of blacklisted names.
  # If the suggested name is blacklisted, appends a number to get a unique name.

  def find_available_name(basename, used_names), do:
    find_available_name(to_string(basename), used_names, "", 0)


  # Generates a name given a suggested "base" name, and a set of blacklisted names.
  # If the suggested name is blacklisted, prepends the given prefix. If that name
  # is also blacklisted, appends a number to the prefix.

  def find_available_name(basename, used_names, prefix), do:
    find_available_name(to_string(basename), used_names, prefix, 1)


  # Generates a name given a suggested "base" name, and a set of blacklisted names.
  # If the suggested name is blacklisted, prepends the given prefix. If that name
  # is also blacklisted, appends a number to the prefix. You can specify the first
  # number to use. 0 indicates no number (i.e. it will try the prefix by itself).

  def find_available_name(basename, used_names, prefix, val) do
    suggestion = suggest_name(basename, prefix, val)
    if Set.member?(used_names, suggestion) do
      find_available_name(basename, used_names, prefix, val + 1)
    else
      suggestion
    end
  end


  # Given a string, returns it with the first letter lowercased. Generally used
  # to convert variable names to Elixir form.

  def lower_str("_"), do: "_"
  def lower_str(<< "_" :: utf8, rest :: binary >>), do:
    << "_" :: utf8, lower_str(rest) :: binary >>
  def lower_str(<< first :: utf8, rest :: binary >>), do:
    << String.downcase(<< first >>) :: binary, rest :: binary >>


  # Same as lower_str/1 but takes an atom and returns an atom.

  def lower_atom(atom), do:
    atom |> Atom.to_string |> lower_str |> String.to_atom


  # Internal function used by find_available_name, to suggest a name.

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
