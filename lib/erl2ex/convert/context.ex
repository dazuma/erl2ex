
defmodule Erl2ex.Convert.Context do

  @moduledoc false

  alias Erl2ex.Convert.Context
  alias Erl2ex.Convert.Utils


  # These are not allowed as names of functions
  @elixir_reserved_words [
    :do,
    :else,
    :end,
    :false,
    :fn,
    :nil,
    :true,
  ] |> Enum.into(MapSet.new)


  defstruct cur_file_path: nil,
            funcs: %{},
            types: %{},
            macros: %{},
            records: %{},
            used_func_names: MapSet.new,
            used_attr_names: MapSet.new,
            specs: %{},
            variable_map: %{},
            stringification_map: %{},
            quoted_variables: [],
            match_level: 0,
            in_func_params: false,
            match_vars: MapSet.new,
            scopes: []

  defmodule FuncInfo do
    @moduledoc false
    defstruct func_name: nil,
              arities: %{}  # Map of arity to exported flag
  end

  defmodule TypeInfo do
    @moduledoc false
    defstruct arities: %{}  # Map of arity to exported flag
  end

  defmodule MacroInfo do
    @moduledoc false
    defstruct func_name: nil,
              define_tracker: nil,
              requires_init: nil
  end

  defmodule RecordInfo do
    @moduledoc false
    defstruct func_name: nil,
              fields: []
  end


  def build(erl_module, opts) do
    context = build(opts)
    context = Enum.reduce(erl_module.forms, context, &collect_func_info/2)
    context = Enum.reduce(context.funcs, context, &assign_strange_func_names/2)
    context = Enum.reduce(erl_module.exports, context, &collect_exports/2)
    context = Enum.reduce(erl_module.type_exports, context, &collect_type_exports/2)
    context = Enum.reduce(erl_module.forms, context, &collect_attr_info/2)
    context = Enum.reduce(erl_module.forms, context, &collect_record_info/2)
    context = Enum.reduce(erl_module.forms, context, &collect_macro_info/2)
    context = Enum.reduce(erl_module.specs, context, &collect_specs/2)
    context
  end


  def build(opts) do
    %Context{
      cur_file_path: Keyword.get(opts, :cur_file_path, nil),
    }
  end


  def set_variable_maps(context, expr, extra_omits \\ []) do
    {variable_map, stringification_map} = compute_var_maps(context, expr, extra_omits)

    quoted_vars = extra_omits
      |> Enum.map(&(Map.fetch!(variable_map, &1)))
    context = %Context{context |
      quoted_variables: quoted_vars ++ Map.values(stringification_map),
      variable_map: variable_map,
      stringification_map: stringification_map
    }
    context
  end


  def push_match_level(context = %Context{match_level: old_match_level, in_func_params: old_in_func_params}, in_func_params) do
    %Context{context |
      match_level: old_match_level + 1,
      in_func_params: old_in_func_params or in_func_params
    }
  end


  def pop_match_level(context = %Context{scopes: scopes, match_vars: match_vars, match_level: old_match_level, in_func_params: in_func_params}) do
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


  def push_scope(context = %Context{scopes: scopes}) do
    %Context{context | scopes: [{MapSet.new, MapSet.new} | scopes]}
  end


  def pop_scope(context = %Context{scopes: [_h]}) do
    %Context{context | scopes: []}
  end

  def pop_scope(context = %Context{scopes: [{top_vars, _top_exports}, {next_vars, next_exports} | t]}) do
    next_exports = MapSet.union(next_exports, top_vars)
    %Context{context | scopes: [{next_vars, next_exports} | t]}
  end


  def clear_exports(context = %Context{scopes: [{top_vars, _top_exports} | t]}) do
    %Context{context | scopes: [{top_vars, MapSet.new} | t]}
  end

  def clear_exports(context = %Context{scopes: []}) do
    context
  end


  def apply_exports(context = %Context{scopes: [{top_vars, top_exports} | t]}) do
    top_vars = MapSet.union(top_vars, top_exports)
    %Context{context | scopes: [{top_vars, MapSet.new} | t]}
  end

  def apply_exports(context = %Context{scopes: []}) do
    context
  end


  def is_exported?(context, name, arity) do
    info = Map.get(context.funcs, name, %FuncInfo{})
    Map.get(info.arities, arity, false)
  end


  def is_type_exported?(context, name, arity) do
    info = Map.get(context.types, name, %TypeInfo{})
    Map.get(info.arities, arity, false)
  end


  def is_local_func?(context, name, arity) do
    info = Map.get(context.funcs, name, %FuncInfo{})
    Map.has_key?(info.arities, arity)
  end


  def is_quoted_var?(context, name) do
    Enum.member?(context.quoted_variables, name)
  end


  def local_function_name(context, name) do
    Map.fetch!(context.funcs, name).func_name
  end


  def macro_function_name(context, name) do
    Map.fetch!(context.macros, name).func_name |> ensure_exists
  end


  def record_function_name(context, name) do
    Map.fetch!(context.records, name).func_name
  end


  def record_field_index(context, record_name, field_name) do
    (Map.fetch!(context.records, record_name).fields
      |> Enum.find_index(fn f -> f == field_name end)) + 1
  end


  def record_field_names(context, record_name) do
    Map.fetch!(context.records, record_name).fields
  end


  def map_records(context, func) do
    context.records |>
      Enum.map(fn {name, %RecordInfo{fields: fields}} ->
        func.(name, fields)
      end)
  end


  def tracking_attr_name(context, name) do
    Map.fetch!(context.macros, name).define_tracker
  end


  def specs_for_func(context, name) do
    Map.get(context.specs, name, %Erl2ex.ErlSpec{name: name})
  end


  def map_variable_name(context, name) do
    mapped_name = Map.fetch!(context.variable_map, name)
    needs_caret = false
    if context.match_level > 0 do
      needs_caret = not context.in_func_params and name != :_ and variable_seen?(context.scopes, name)
      if not needs_caret and name != :_ do
        context = %Context{context |
          match_vars: MapSet.put(context.match_vars, name)
        }
      end
    end
    {mapped_name, needs_caret, context}
  end


  def cur_file_path_for_display(%Context{cur_file_path: nil}), do:
    "(Unknown source file)"

  def cur_file_path_for_display(%Context{cur_file_path: path}), do:
    path


  def macros_that_need_init(%Context{macros: macros}) do
    macros |> Enum.filter_map(
      fn
        {_, %MacroInfo{requires_init: true}} -> true
        _ -> false
      end,
      fn {name, %MacroInfo{define_tracker: define_tracker}} ->
        {name, define_tracker}
      end)
  end


  defp compute_var_maps(context, expr, extra_omits) do
    {normal_vars, _consts, stringified_args} = expr
      |> collect_variable_names(MapSet.new)
      |> MapSet.union(extra_omits |> Enum.into(MapSet.new))
      |> classify_var_names()

    all_names = context.used_func_names
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
        |> Utils.find_available_name(all_names, "str")
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


  defp ensure_exists(x) when x != nil, do: x


  defp collect_func_info(%Erl2ex.ErlFunc{name: name, arity: arity, clauses: clauses}, context) do
    context = add_func_info({name, arity}, context)
    collect_func_ref_names(clauses, context)
  end
  defp collect_func_info(%Erl2ex.ErlDefine{replacement: replacement}, context) do
    collect_func_ref_names(replacement, context)
  end
  defp collect_func_info(%Erl2ex.ErlImport{funcs: funcs}, context) do
    Enum.reduce(funcs, context, &add_func_info/2)
  end
  defp collect_func_info(_, context), do: context

  defp add_func_info({name, arity}, context) do
    func_name = nil
    used_func_names = context.used_func_names
    if is_valid_elixir_func_name(name) do
      func_name = name
      used_func_names = MapSet.put(used_func_names, name)
    end
    func_info = Map.get(context.funcs, name, %FuncInfo{func_name: func_name})
    func_info = %FuncInfo{func_info |
      arities: Map.put(func_info.arities, arity, false)
    }
    %Context{context |
      funcs: Map.put(context.funcs, name, func_info),
      used_func_names: used_func_names
    }
  end

  defp collect_func_ref_names({:call, _, {:atom, _, name}, args}, context) do
    context = collect_func_ref_names(args, context)
    %Context{context |
      used_func_names: MapSet.put(context.used_func_names, name)
    }
  end
  defp collect_func_ref_names(tuple, context) when is_tuple(tuple) do
    collect_func_ref_names(Tuple.to_list(tuple), context)
  end
  defp collect_func_ref_names(list, context) when is_list(list) do
    list |> Enum.reduce(context, &collect_func_ref_names/2)
  end
  defp collect_func_ref_names(_, context), do: context


  defp is_valid_elixir_func_name(name) do
    Regex.match?(~r/^[_a-z]\w*$/, Atom.to_string(name)) and
      not MapSet.member?(@elixir_reserved_words, name)
  end


  defp assign_strange_func_names({name, info = %FuncInfo{func_name: nil}}, context) do
    mangled_name = Regex.replace(~r/\W/, Atom.to_string(name), "_")
    elixir_name = mangled_name
      |> Utils.find_available_name(context.used_func_names, "func")
    info = %FuncInfo{info | func_name: elixir_name}
    %Context{context |
      funcs: Map.put(context.funcs, name, info),
      used_func_names: MapSet.put(context.used_func_names, elixir_name)
    }
  end
  defp assign_strange_func_names(_, context), do: context


  defp collect_type_exports({name, arity}, context) do
    type_info = Map.get(context.types, name, %TypeInfo{})
    type_info = %TypeInfo{type_info |
      arities: Map.put(type_info.arities, arity, true)
    }
    %Context{context |
      types: Map.put(context.types, name, type_info)
    }
  end


  defp collect_exports({name, arity}, context) do
    func_info = Map.fetch!(context.funcs, name)
    func_info = %FuncInfo{func_info |
      arities: Map.put(func_info.arities, arity, true)
    }
    %Context{context |
      funcs: Map.put(context.funcs, name, func_info)
    }
  end


  defp collect_attr_info(%Erl2ex.ErlAttr{name: name}, context) do
    %Context{context |
      used_attr_names: MapSet.put(context.used_attr_names, name)
    }
  end
  defp collect_attr_info(_, context), do: context


  defp collect_record_info(%Erl2ex.ErlRecord{name: name, fields: fields}, context) do
    macro_name = Utils.find_available_name(name, context.used_func_names, "erlrecord")
    record_info = %RecordInfo{
      func_name: macro_name,
      fields: fields |> Enum.map(&extract_record_field_name/1)
    }
    %Context{context |
      used_func_names: MapSet.put(context.used_func_names, macro_name),
      records: Map.put(context.records, name, record_info)
    }
  end
  defp collect_record_info(_, context), do: context


  defp collect_macro_info(%Erl2ex.ErlDefine{name: name}, context) do
    macro = Map.get(context.macros, name, %MacroInfo{})
    if macro.func_name == nil do
      macro_name = Utils.find_available_name(name, context.used_func_names, "erlmacro")
      nmacro = %MacroInfo{macro |
        func_name: macro_name,
        requires_init: update_requires_init(macro.requires_init, false)
      }
      %Context{context |
        macros: Map.put(context.macros, name, nmacro),
        used_func_names: MapSet.put(context.used_func_names, macro_name)
      }
    else
      context
    end
  end

  defp collect_macro_info(%Erl2ex.ErlDirective{name: name}, context) when name != nil do
    macro = Map.get(context.macros, name, %MacroInfo{})
    if macro.define_tracker == nil do
      tracker_name = Utils.find_available_name(name, context.used_attr_names, "defined")
      nmacro = %MacroInfo{macro |
        define_tracker: tracker_name,
        requires_init: update_requires_init(macro.requires_init, true)
      }
      %Context{context |
        macros: Map.put(context.macros, name, nmacro),
        used_attr_names: MapSet.put(context.used_attr_names, tracker_name)
      }
    else
      context
    end
  end

  defp collect_macro_info(_, context), do: context


  defp collect_specs(spec = %Erl2ex.ErlSpec{name: name}, context), do:
    %Context{context | specs: Map.put(context.specs, name, spec)}


  defp extract_record_field_name({:typed_record_field, record_field, _type}), do:
    extract_record_field_name(record_field)
  defp extract_record_field_name({:record_field, _, {:atom, _, name}}), do: name
  defp extract_record_field_name({:record_field, _, {:atom, _, name}, _}), do: name


  defp update_requires_init(nil, nval), do: nval
  defp update_requires_init(oval, _nval), do: oval


end
