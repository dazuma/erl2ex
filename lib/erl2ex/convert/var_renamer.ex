
defmodule Erl2ex.Convert.VarRenamer do

  @moduledoc false

  alias Erl2ex.Convert.Utils


  def compute_var_maps(expr, extras \\ []) do
    {var_names, func_names} = expr
      |> collect_variable_names({HashSet.new, HashSet.new})
    var_names = var_names |> HashSet.union(extras |> Enum.into(HashSet.new))
    {normal_vars, _consts, stringified_args} = classify_var_names(var_names)

    all_names = func_names
    {variables_map, all_names} = normal_vars
      |> Enum.reduce({HashDict.new, all_names}, &map_variables/2)
    {stringification_map, variables_map, _all_names} = stringified_args
      |> Enum.reduce({HashDict.new, variables_map, all_names}, &map_stringification/2)
    {variables_map, stringification_map}
  end


  defp collect_variable_names({:var, _, var}, {var_names, func_names}), do:
    {HashSet.put(var_names, var), func_names}

  defp collect_variable_names({:call, _, {:atom, _, name}, args}, results) do
    {var_names, func_names} = collect_variable_names(args, results)
    {var_names, HashSet.put(func_names, name)}
  end

  defp collect_variable_names(tuple, results) when is_tuple(tuple), do:
    collect_variable_names(Tuple.to_list(tuple), results)

  defp collect_variable_names(list, results) when is_list(list), do:
    list |> Enum.reduce(results, &collect_variable_names/2)

  defp collect_variable_names(_, results), do: results


  defp classify_var_names(var_names) do
    groups = var_names
      |> Enum.group_by(fn var ->
        name = var |> Atom.to_string
        cond do
          String.starts_with?(name, "??") -> :stringification
          String.starts_with?(name, "?") -> :const
          true -> :normal
        end
      end)
    {
      Map.get(groups, :normal, []),
      Map.get(groups, :const, []),
      Map.get(groups, :stringification, [])
    }
  end


  defp map_stringification(stringified_arg, {stringification_map, variables_map, all_names}) do
    if not HashDict.has_key?(stringification_map, stringified_arg) do
      arg_name = stringified_arg
        |> Atom.to_string
        |> String.lstrip(??)
        |> String.to_atom
      mapped_arg = HashDict.fetch!(variables_map, arg_name)
      mangled_name = mapped_arg
        |> Utils.find_available_name(all_names, "str")
      variables_map = HashDict.put(variables_map, stringified_arg, mangled_name)
      stringification_map = HashDict.put(stringification_map, mapped_arg, mangled_name)
      all_names = HashSet.put(all_names, mangled_name)
    end
    {stringification_map, variables_map, all_names}
  end


  defp map_variables(var_name, {variables_map, all_names}) do
    if not HashDict.has_key?(variables_map, var_name) do
      mapped_name = var_name
        |> Atom.to_string
        |> Utils.lower_str
        |> Utils.find_available_name(all_names, "var", 0)
      variables_map = HashDict.put(variables_map, var_name, mapped_name)
      all_names = HashSet.put(all_names, mapped_name)
    end
    {variables_map, all_names}
  end

end
