
defmodule Erl2ex.Convert.Context do

  @moduledoc false

  alias Erl2ex.Analyze
  alias Erl2ex.Utils
  alias Erl2ex.Convert.Context


  defstruct analyzed_module: nil,
            cur_file_path: nil,
            used_func_names: MapSet.new,
            variable_map: %{},
            stringification_map: %{},
            quoted_variables: [],
            match_level: 0,
            in_bin_size_expr: false,
            in_func_params: false,
            in_macro_def: false,
            match_vars: MapSet.new,
            scopes: [],
            macro_exports: %{},
            macro_export_collection_stack: [],
            cur_record_types: [],
            record_types: %{}


  def build(analyzed_module, opts) do
    %Context{
      analyzed_module: analyzed_module,
      cur_file_path: Keyword.get(opts, :cur_file_path, nil),
      used_func_names: analyzed_module.used_func_names
    }
  end


  def set_variable_maps(context, expr, macro_args \\ []) do
    {variable_map, stringification_map} = compute_var_maps(context, expr, macro_args)

    quoted_vars = macro_args
      |> Enum.map(&(Map.fetch!(variable_map, &1)))
    %Context{context |
      quoted_variables: quoted_vars ++ Map.values(stringification_map),
      variable_map: variable_map,
      stringification_map: stringification_map
    }
  end


  def clear_variable_maps(context) do
    %Context{context |
      quoted_variables: [],
      variable_map: %{},
      stringification_map: %{}
    }
  end


  def start_macro_export_collection(context, args) do
    index_map = args |> Enum.with_index |> Enum.into(%{})
    collector = {MapSet.new, index_map}
    %Context{context |
      macro_export_collection_stack: [collector | context.macro_export_collection_stack]
    }
  end


  def suspend_macro_export_collection(context) do
    %Context{context |
      macro_export_collection_stack: [{MapSet.new, nil} | context.macro_export_collection_stack]
    }
  end


  def resume_macro_export_collection(context) do
    %Context{context |
      macro_export_collection_stack: tl(context.macro_export_collection_stack)
    }
  end


  def finish_macro_export_collection(context, name, arity) do
    [{indexes, _} | macro_export_collection_stack] = context.macro_export_collection_stack
    macro_exports = context.macro_exports |> Map.put({name, arity}, indexes)
    %Context{context |
      macro_exports: macro_exports,
      macro_export_collection_stack: macro_export_collection_stack
    }
  end


  def add_macro_export(context, erl_var) do
    case context.macro_export_collection_stack do
      [{_indexes, nil} | _tail] ->
        context
      [{indexes, index_map} | stack_tail] ->
        case Map.fetch(index_map, erl_var) do
          {:ok, index} ->
            %Context{context |
              macro_export_collection_stack: [{MapSet.put(indexes, index), index_map} | stack_tail]
            }
          :error ->
            context
        end
      [] ->
        context
    end
  end


  def get_macro_export_indexes(%Context{macro_exports: macro_exports}, name, arity) do
    Map.fetch!(macro_exports, {name, arity})
  end


  def push_match_level(
    %Context{
      match_level: old_match_level,
      in_func_params: old_in_func_params
    } = context,
    in_func_params)
  do
    %Context{context |
      match_level: old_match_level + 1,
      in_func_params: old_in_func_params or in_func_params
    }
  end


  def pop_match_level(
    %Context{
      scopes: scopes,
      match_vars: match_vars,
      match_level: old_match_level,
      in_func_params: in_func_params
    } = context)
  do
    if old_match_level == 1 do
      in_func_params = false
      [{top_vars, top_exports} | other_scopes] = scopes
      top_vars = MapSet.union(top_vars, match_vars)
      scopes = [{top_vars, top_exports} | other_scopes]
      match_vars = MapSet.new
    end
    %Context{context |
      match_level: old_match_level - 1,
      in_func_params: in_func_params,
      scopes: scopes,
      match_vars: match_vars
    }
  end


  def push_scope(%Context{scopes: scopes} = context) do
    %Context{context | scopes: [{MapSet.new, MapSet.new} | scopes]}
  end


  def pop_scope(%Context{scopes: [_h]} = context) do
    %Context{context | scopes: []}
  end

  def pop_scope(%Context{scopes: [{top_vars, _top_exports}, {next_vars, next_exports} | t]} = context) do
    next_exports = MapSet.union(next_exports, top_vars)
    %Context{context | scopes: [{next_vars, next_exports} | t]}
  end


  def clear_exports(%Context{scopes: [{top_vars, _top_exports} | t]} = context) do
    %Context{context | scopes: [{top_vars, MapSet.new} | t]}
  end

  def clear_exports(%Context{scopes: []} = context) do
    context
  end


  def apply_exports(%Context{scopes: [{top_vars, top_exports} | t]} = context) do
    top_vars = MapSet.union(top_vars, top_exports)
    %Context{context | scopes: [{top_vars, MapSet.new} | t]}
  end

  def apply_exports(%Context{scopes: []} = context) do
    context
  end


  def is_quoted_var?(%Context{quoted_variables: quoted_variables}, name) do
    Enum.member?(quoted_variables, name)
  end


  def is_unhygenized_var?(
    %Context{
      macro_export_collection_stack: macro_export_collection_stack,
      match_level: match_level,
      quoted_variables: quoted_variables
    },
    name)
  do
    not Enum.empty?(macro_export_collection_stack) and
        elem(hd(macro_export_collection_stack), 1) != nil and
        not Enum.member?(quoted_variables, name)
  end


  def generate_macro_name(%Context{used_func_names: used_func_names} = context, name, arity) do
    prefix = if arity == nil, do: "erlconst", else: "erlmacro"
    func_name = Utils.find_available_name(name, used_func_names, prefix)
    context = %Context{context |
      used_func_names: MapSet.put(used_func_names, func_name)
    }
    {func_name, context}
  end


  def map_variable_name(context, name) do
    mapped_name = Map.fetch!(context.variable_map, name)
    needs_caret = false
    if not context.in_bin_size_expr and context.match_level > 0 and name != :_ do
      needs_caret = not context.in_func_params and variable_seen?(context.scopes, name)
      if not needs_caret do
        context = %Context{context |
          match_vars: MapSet.put(context.match_vars, name)
        }
      end
    end
    {mapped_name, needs_caret, context}
  end


  def start_bin_size_expr(context) do
    %Context{context | in_bin_size_expr: true}
  end


  def finish_bin_size_expr(context) do
    %Context{context | in_bin_size_expr: false}
  end


  def cur_file_path_for_display(%Context{cur_file_path: nil}), do:
    "(Unknown source file)"

  def cur_file_path_for_display(%Context{cur_file_path: path}), do:
    path


  def start_record_types(context) do
    %Context{context |
      cur_record_types: []
    }
  end


  def add_record_type(context, field, type) do
    %Context{context |
      cur_record_types: [{field, type} | context.cur_record_types]
    }
  end


  def finish_record_types(context, name) do
    %Context{context |
      record_types: Map.put(context.record_types, name, Enum.reverse(context.cur_record_types)),
      cur_record_types: []
    }
  end


  def get_record_types(%Context{record_types: record_types}, name) do
    Map.fetch!(record_types, name)
  end


  def handle_error(context, expr, ast_context \\ nil) do
    ast_context = if ast_context, do: " #{ast_context}", else: ""
    raise CompileError,
      file: cur_file_path_for_display(context),
      line: find_error_line(expr),
      description: "Unrecognized Erlang expression#{ast_context}: #{inspect(expr)}"
  end


  defp find_error_line(expr) when is_tuple(expr) and tuple_size(expr) >= 3, do: elem(expr, 1)
  defp find_error_line([expr | _]), do: find_error_line(expr)
  defp find_error_line(_), do: :unknown


  defp compute_var_maps(context, expr, extra_omits) do
    {normal_vars, _consts, stringified_args} = expr
      |> collect_variable_names(MapSet.new)
      |> MapSet.union(extra_omits |> Enum.into(MapSet.new))
      |> classify_var_names()

    all_names = MapSet.union(context.used_func_names, Analyze.elixir_reserved_words)
    {variables_map, all_names} = normal_vars
      |> Enum.reduce({%{}, all_names}, &map_variables/2)
    {stringification_map, variables_map, _all_names} = stringified_args
      |> Enum.reduce({%{}, variables_map, all_names}, &map_stringification/2)
    {variables_map, stringification_map}
  end


  defp collect_variable_names({:var, _, var}, var_names), do:
    MapSet.put(var_names, var)

  defp collect_variable_names(tuple, var_names) when is_tuple(tuple), do:
    collect_variable_names(Tuple.to_list(tuple), var_names)

  defp collect_variable_names(list, var_names) when is_list(list), do:
    list |> Enum.reduce(var_names, &collect_variable_names/2)

  defp collect_variable_names(_, var_names), do: var_names


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
    if not Map.has_key?(stringification_map, stringified_arg) do
      arg_name = stringified_arg
        |> Atom.to_string
        |> String.lstrip(??)
        |> String.to_atom
      mapped_arg = Map.fetch!(variables_map, arg_name)
      mangled_name = mapped_arg
        |> Utils.find_available_name(all_names, "str", 1)
      variables_map = Map.put(variables_map, stringified_arg, mangled_name)
      stringification_map = Map.put(stringification_map, mapped_arg, mangled_name)
      all_names = MapSet.put(all_names, mangled_name)
    end
    {stringification_map, variables_map, all_names}
  end


  defp map_variables(var_name, {variables_map, all_names}) do
    if not Map.has_key?(variables_map, var_name) do
      mapped_name = var_name
        |> Atom.to_string
        |> Utils.lower_str
        |> Utils.find_available_name(all_names, "var", 0)
      variables_map = Map.put(variables_map, var_name, mapped_name)
      all_names = MapSet.put(all_names, mapped_name)
    end
    {variables_map, all_names}
  end


  defp variable_seen?([], _name), do: false
  defp variable_seen?([{scopes_h, _} | scopes_t], name) do
    if MapSet.member?(scopes_h, name) do
      true
    else
      variable_seen?(scopes_t, name)
    end
  end

end
