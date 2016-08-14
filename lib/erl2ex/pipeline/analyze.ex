# This is the third phase in the pipeline, after file include inlining.
# We analyze the parsed forms and gather a set of module-wide information
# needed for later phases. The information is represented by ModuleData.

defmodule Erl2ex.Pipeline.Analyze do

  @moduledoc false

  alias Erl2ex.Pipeline.ErlSyntax
  alias Erl2ex.Pipeline.ModuleData
  alias Erl2ex.Pipeline.ModuleData.MacroData
  alias Erl2ex.Pipeline.ModuleData.RecordData
  alias Erl2ex.Pipeline.Names
  alias Erl2ex.Pipeline.Utils


  # Run all the analyses on the given list of forms, and return a ModuleData.

  def forms(forms_list, opts \\ []) do
    forms_list
      |> build_base_data(opts)
      |> collect(forms_list, &handle_form_for_name_and_exports/2)
      |> collect(forms_list, &handle_form_for_used_attr_names/2)
      |> collect(forms_list, &handle_form_for_funcs/2)
      |> assign_local_func_names
      |> collect(forms_list, &handle_form_for_records/2)
      |> collect(forms_list, &handle_form_for_macros/2)
  end


  # Initialize the ModuleData.

  defp build_base_data(forms_list, opts) do
    default_imports = Names.elixir_auto_imports
      |> Enum.map(fn {name, arities} ->
        arity_info = arities
          |> Enum.map(fn arity -> {arity, Kernel} end)
          |> Enum.into(%{})
        {name, arity_info}
      end)
      |> Enum.into(%{})
    auto_export_suffixes = Keyword.get_values(opts, :auto_export_suffix)

    %ModuleData{
      forms: forms_list,
      imported_funcs: default_imports,
      used_func_names: default_imports |> Map.keys |> Enum.into(MapSet.new),
      auto_export_suffixes: auto_export_suffixes
    }
  end


  # A version of Enum.reduce with the accumulator and elements arguments
  # reversed. Useful for chaining: the result of one reduction can be passed
  # into the next.

  defp collect(accumulator, elements, fun), do:
    Enum.reduce(elements, accumulator, fun)


  # An analysis of the extended (epp_dodger) AST that extracts the module
  # name, exports, and imports.

  defp handle_form_for_name_and_exports({_erl_ast, form_node}, module_data) do
    ErlSyntax.on_static_attribute(form_node, module_data, fn attr_name, arg_nodes ->
      case attr_name do
        :module ->
          ErlSyntax.on_trees1(arg_nodes, module_data, fn arg_node ->
            ErlSyntax.on_atom(arg_node, module_data, fn value ->
              %ModuleData{module_data | name: value}
            end)
          end)
        :export ->
          ErlSyntax.on_trees1(arg_nodes, module_data, fn arg_node ->
            ErlSyntax.on_arity_qualifier_list(arg_node, module_data, fn(mod_data, name, arity) ->
              exports = mod_data.exports
                |> MapSet.put({name, arity})
                |> MapSet.put(name)
              %ModuleData{mod_data |
                exports: exports
              }
            end)
          end)
        :export_type ->
          ErlSyntax.on_trees1(arg_nodes, module_data, fn arg_node ->
            ErlSyntax.on_type_with_arity_list(arg_node, module_data, fn(mod_data, name, arity) ->
              %ModuleData{mod_data |
                type_exports: MapSet.put(mod_data.type_exports, {name, arity})
              }
            end)
          end)
        :import ->
          if Enum.count(arg_nodes) == 2 do
            [module_name_node, func_nodes] = arg_nodes
            ErlSyntax.on_atom(module_name_node, module_data, fn module_name ->
              ErlSyntax.on_arity_qualifier_list(func_nodes, module_data, fn(mod_data, name, arity) ->
                arity_map = mod_data.imported_funcs
                  |> Map.get(name, %{})
                  |> Map.put(arity, module_name)
                %ModuleData{mod_data |
                  imported_funcs: Map.put(mod_data.imported_funcs, name, arity_map),
                  used_func_names: MapSet.put(mod_data.used_func_names, name)
                }
              end)
            end)
          else
            module_data
          end
        _ ->
          module_data
      end
    end)
  end


  # An analysis of the extended (epp_dodger) AST that extracts the names of
  # attributes defined in the module.

  defp handle_form_for_used_attr_names({_erl_ast, form_node}, module_data) do
    ErlSyntax.on_static_attribute(form_node, module_data, fn attr_name, _arg_nodes ->
      if Names.special_attr_name?(attr_name) do
        module_data
      else
        %ModuleData{module_data |
          used_attr_names: MapSet.put(module_data.used_attr_names, attr_name)
        }
      end
    end)
  end


  # An analysis of the extended (epp_dodger) AST that extracts names of all
  # the functions defined in the module. It also decides which functions
  # should be renamed because of name collision with imports, reserved words,
  # and other Elixir naming inconveniences.
  #
  # Note that renaming will take place only for private functions. An exported
  # function is part of the module interface and cannot be renamed. This
  # analysis must therefore take place after the import/export analysis.
  #
  # After this analysis, local_funcs will have a complete list of functions
  # in this module. func_rename_map will contain only non-renamed functions.
  # Any local_funcs not already in func_rename_map need to have new names
  # assigned.

  defp handle_form_for_funcs({_erl_ast, form_node}, module_data) do
    ErlSyntax.on_type(form_node, :function, module_data, fn ->
      arity = :erl_syntax.function_arity(form_node)
      name_node = :erl_syntax.function_name(form_node)
      ErlSyntax.on_atom(name_node, module_data, fn name ->
        module_data = %ModuleData{module_data |
          local_funcs: MapSet.put(module_data.local_funcs, {name, arity})
        }
        func_rename_map = module_data.func_rename_map
        if not Map.has_key?(func_rename_map, name) and
          (MapSet.member?(module_data.exports, {name, arity}) or
            (Names.local_callable_function_name?(name) and
              not Map.has_key?(module_data.imported_funcs, name)))
        do
          %ModuleData{module_data |
            func_rename_map: Map.put_new(func_rename_map, name, name),
            used_func_names: MapSet.put(module_data.used_func_names, name)
          }
        else
          module_data
        end
      end)
    end)
  end


  # This analysis actually assigns names for renamed functions. It is done
  # strictly after the function name analysis, so that we have a complete list
  # of which names are already taken by exported functions.

  defp assign_local_func_names(module_data) do
    module_data.local_funcs
      |> Enum.reduce(module_data, fn({name, _arity}, cur_data) ->
        func_rename_map = cur_data.func_rename_map
        if Map.has_key?(func_rename_map, name) do
          cur_data
        else
          used_func_names = cur_data.used_func_names
          mangled_name = Regex.replace(~r/\W/, Atom.to_string(name), "_")
          mangled_name = Utils.find_available_name(mangled_name, used_func_names, "func")
          func_rename_map = Map.put(func_rename_map, name, mangled_name)
          used_func_names = MapSet.put(used_func_names, mangled_name)
          %ModuleData{module_data |
            func_rename_map: func_rename_map,
            used_func_names: used_func_names
          }
        end
      end)
  end


  # An analysis of the erl_parse AST that extracts info about every record,
  # primarily the list of fields.
  # It decides two additional items: a name to use for the record's macro, and
  # a name to use for the attribute that holds its field info. Those names
  # are uniquified; thus, this analysis must run after the function and
  # attribute analyses so we don't take names needed by exported items.
  #
  # The analysis also digs through function and macro definitions looking for
  # record queries so we can determine whether to emit code to support them.

  defp handle_form_for_records(
    {{:attribute, _line, :record, {recname, fields}}, _form_node}, module_data)
  do
    macro_name = Utils.find_available_name(
        recname, module_data.used_func_names, "erlrecord")
    data_name = Utils.find_available_name(
        recname, module_data.used_attr_names, "erlrecordfields")
    field_info = fields |> Enum.map(&extract_record_field_info/1)
    record_info = %RecordData{
      func_name: macro_name,
      data_attr_name: data_name,
      fields: field_info
    }
    %ModuleData{module_data |
      records: Map.put(module_data.records, recname, record_info),
      used_func_names: MapSet.put(module_data.used_func_names, macro_name),
      used_attr_names: MapSet.put(module_data.used_attr_names, data_name)
    }
  end

  defp handle_form_for_records(
    {{:function, _line, _name, _arity, clauses}, _form_node}, module_data)
  do
    detect_record_query_presence(clauses, module_data)
  end

  defp handle_form_for_records(
    {{:define, _line, _macro, replacement}, _form_node}, module_data)
  do
    detect_record_query_presence(replacement, module_data)
  end

  defp handle_form_for_records(_form, module_data), do: module_data


  # Extract information from a record field node in the erl_parse tree.

  defp extract_record_field_info({:typed_record_field, record_field, type}) do
    {name, _line} = interpret_record_field(record_field)
    {name, type}
  end
  defp extract_record_field_info(record_field) do
    {name, line} = interpret_record_field(record_field)
    {name, {:type, line, :term, []}}
  end

  defp interpret_record_field({:record_field, _, {:atom, line, name}}), do: {name, line}
  defp interpret_record_field({:record_field, _, {:atom, line, name}, _}), do: {name, line}


  # Look for record_info and record_index expressions in the erl_parse AST,
  # and, if found, allocate a name for the corresponding Elixir macros.

  defp detect_record_query_presence({:call, _, {:atom, _, :is_record}, _}, module_data), do:
    %ModuleData{module_data | has_is_record: true}
  defp detect_record_query_presence(
    {:call, _, {:atom, _, :record_info}, [{:atom, _, :size}, _]}, module_data)
  do
    set_record_size_macro(module_data)
  end
  defp detect_record_query_presence({:record_index, _, _, _}, module_data), do:
    set_record_index_macro(module_data)
  defp detect_record_query_presence(tuple, module_data) when is_tuple(tuple), do:
    detect_record_query_presence(Tuple.to_list(tuple), module_data)
  defp detect_record_query_presence(list, module_data) when is_list(list), do:
    list |> Enum.reduce(module_data, &detect_record_query_presence/2)
  defp detect_record_query_presence(_, module_data), do: module_data

  defp set_record_size_macro(
    %ModuleData{record_size_macro: nil, used_func_names: used_func_names} = module_data)
  do
    macro_name = Utils.find_available_name("erlrecordsize", used_func_names)
    %ModuleData{module_data |
      record_size_macro: macro_name,
      used_func_names: MapSet.put(used_func_names, macro_name)
    }
  end
  defp set_record_size_macro(module_data), do: module_data

  defp set_record_index_macro(
    %ModuleData{record_index_macro: nil, used_func_names: used_func_names} = module_data)
  do
    macro_name = Utils.find_available_name("erlrecordindex", used_func_names)
    %ModuleData{module_data |
      record_index_macro: macro_name,
      used_func_names: MapSet.put(used_func_names, macro_name)
    }
  end
  defp set_record_index_macro(module_data), do: module_data


  # An analysis of the erl_parse AST that extracts info about every macro.
  # This collects a wide variety of information, represented in the
  # ModuleData.MacroData structure. In particular, we follow uses and
  # definitions of the macro, and determine whether the macro is defined
  # once and can be invoked directly from Elixir, or whether it may be
  # redefined in Erlang, which means it needs to be dispatched in Elixir
  # because Elixir does not allow macro redefinition.

  # When we encounter a macro definition form, analyze and update the data
  # on that macro. Also look for macro calls.
  defp handle_form_for_macros(
    {{:define, _line, macro, replacement}, _form_node}, module_data)
  do
    {name, args} = interpret_macro_expr(macro)
    macro = Map.get(module_data.macros, name, %MacroData{})
    requires_init = update_requires_init(macro.requires_init, false)
    macro = %MacroData{macro | requires_init: requires_init}
    next_is_redefined = update_is_redefined(macro.is_redefined, args)
    module_data = update_macro_info(macro, next_is_redefined, args, name, replacement, module_data)
    detect_func_style_call(replacement, module_data)
  end

  # When we encounter a macro defintion directive, update our information about
  # whether definition state needs to be tracked.
  defp handle_form_for_macros(
    {{:attribute, _line, directive, name}, _form_node}, module_data)
  when directive == :ifdef or directive == :ifndef or directive == :undef
  do
    name = interpret_macro_name(name)
    macro = Map.get(module_data.macros, name, %MacroData{})
    if macro.define_tracker == nil do
      tracker_name = Utils.find_available_name(name, module_data.used_attr_names, "defined")
      macro = %MacroData{macro |
        define_tracker: tracker_name,
        requires_init: update_requires_init(macro.requires_init, true)
      }
      %ModuleData{module_data |
        macros: Map.put(module_data.macros, name, macro),
        used_attr_names: MapSet.put(module_data.used_attr_names, tracker_name)
      }
    else
      module_data
    end
  end

  # When we encounter a function, search it for macro calls.
  defp handle_form_for_macros(
    {{:function, _line, _name, _arity, clauses}, _form_node}, module_data)
  do
    detect_func_style_call(clauses, module_data)
  end

  defp handle_form_for_macros(_, module_data), do: module_data


  # Parse the macro definition expression, which may be a function with
  # arguments, or just a macro name (which may be an atom or variable in
  # Erlang depending on captialization.)

  defp interpret_macro_expr({:call, _, name_expr, arg_exprs}) do
    name = interpret_macro_name(name_expr)
    args = arg_exprs |> Enum.map(fn {:var, _, n} -> n end)
    {name, args}
  end

  defp interpret_macro_expr(macro_expr) do
    name = interpret_macro_name(macro_expr)
    {name, nil}
  end


  # Extract the actual macro name as an atom from the Erlang AST.

  defp interpret_macro_name({:var, _, name}), do: name
  defp interpret_macro_name({:atom, _, name}), do: name
  defp interpret_macro_name(name) when is_atom(name), do: name


  # Search an Erlang AST for macro calls that take arguments. This is used
  # to populate the has_func_style_call field of MacroData.

  defp detect_func_style_call(
    {:call, _, {:var, _, name}, _},
    %ModuleData{
      macros: macros,
      macro_dispatcher: macro_dispatcher,
      used_func_names: used_func_names
    } = module_data)
  do
    case Atom.to_string(name) do
      << "?" :: utf8, basename :: binary >> ->
        macro = Map.get(macros, String.to_atom(basename), %MacroData{})
        macro = %MacroData{macro | has_func_style_call: true}
        {macro_dispatcher, used_func_names} =
          if macro_dispatcher == nil and macro.func_name == nil do
            macro_dispatcher2 = Utils.find_available_name("erlmacro", used_func_names)
            {macro_dispatcher2, used_func_names |> MapSet.put(macro_dispatcher2)}
          else
            {macro_dispatcher, used_func_names}
          end
        %ModuleData{module_data |
          macros: Map.put(macros, name, macro),
          macro_dispatcher: macro_dispatcher,
          used_func_names: used_func_names
        }
      _ ->
        module_data
    end
  end

  defp detect_func_style_call(tuple, module_data) when is_tuple(tuple), do:
    detect_func_style_call(Tuple.to_list(tuple), module_data)

  defp detect_func_style_call(list, module_data) when is_list(list), do:
    list |> Enum.reduce(module_data, &detect_func_style_call/2)

  defp detect_func_style_call(_, module_data), do: module_data


  # A function that updates the MacroData based on new information from a
  # macro definition. The arguments are:
  #   * The current MacroData
  #   * Whether this is a redefinition of this macro
  #   * The argument list (or nil for a no-argument definition)
  #   * The name of the macro, as an atom
  #   * The macro replacement, as an Erlang AST
  #   * The old ModuleData to update.

  # This version is called when a no-argument macro is redefined after it has
  # already been redefined at least once.
  defp update_macro_info(
    %MacroData{
      const_name: const_name,
      is_redefined: true
    } = macro,
    true, nil, name, _replacement,
    %ModuleData{
      macros: macros,
      used_attr_names: used_attr_names
    } = module_data)
  do
    {const_name, used_attr_names} = update_macro_name(name, const_name, used_attr_names, "erlconst")
    macro = %MacroData{macro |
      const_name: const_name
    }
    %ModuleData{module_data |
      macros: Map.put(macros, name, macro),
      used_attr_names: used_attr_names
    }
  end

  # This version is called when a macro with arguments is redefined after it
  # has already been redefined at least once.
  defp update_macro_info(
    %MacroData{
      func_name: func_name,
      is_redefined: true
    } = macro,
    true, _args, name, _replacement,
    %ModuleData{
      macros: macros,
      used_attr_names: used_attr_names
    } = module_data)
  do
    {func_name, used_attr_names} = update_macro_name(name, func_name, used_attr_names, "erlmacro")
    macro = %MacroData{macro |
      func_name: func_name
    }
    %ModuleData{module_data |
      macros: Map.put(macros, name, macro),
      used_attr_names: used_attr_names
    }
  end

  # This version is called when a macro is redefined for the first time. It
  # flips the MacroData to request using the macro dispatcher instead of
  # the const_name and func_name.
  defp update_macro_info(
    %MacroData{
      const_name: const_name,
      func_name: func_name
    } = macro,
    true, args, name, _replacement,
    %ModuleData{
      macros: macros,
      macro_dispatcher: macro_dispatcher,
      used_func_names: used_func_names,
      used_attr_names: used_attr_names
    } = module_data)
  do
    used_func_names = used_func_names
      |> MapSet.delete(const_name)
      |> MapSet.delete(func_name)
    {const_name, used_attr_names} =
      if const_name != nil or args == nil do
        update_macro_name(name, nil, used_attr_names, "erlconst")
      else
        {const_name, used_attr_names}
      end
    {func_name, used_attr_names} =
      if func_name != nil or args != nil do
        update_macro_name(name, nil, used_attr_names, "erlmacro")
      else
        {func_name, used_attr_names}
      end
    {macro_dispatcher, used_func_names} =
      if macro_dispatcher == nil do
        macro_dispatcher2 = Utils.find_available_name("erlmacro", used_func_names)
        {macro_dispatcher2, MapSet.put(used_func_names, macro_dispatcher2)}
      else
        {macro_dispatcher, used_func_names}
      end
    macro = %MacroData{macro |
      is_redefined: true,
      const_name: const_name,
      func_name: func_name
    }
    %ModuleData{module_data |
      macros: Map.put(macros, name, macro),
      macro_dispatcher: macro_dispatcher,
      used_func_names: used_func_names,
      used_attr_names: used_attr_names
    }
  end

  # This version is called when a no-argument macro is defined for the first
  # time.
  defp update_macro_info(
    %MacroData{
      const_name: const_name,
    } = macro,
    is_redefined, nil, name, replacement,
    %ModuleData{
      macros: macros,
      used_func_names: used_func_names
    } = module_data)
  do
    replacement_expr = extract_replacement_expr(replacement)
    {const_name, used_func_names} = update_macro_name(name, const_name, used_func_names, "erlconst")
    macro = %MacroData{macro |
      is_redefined: is_redefined,
      const_name: const_name,
      const_expr: replacement_expr
    }
    %ModuleData{module_data |
      macros: Map.put(macros, name, macro),
      used_func_names: used_func_names
    }
  end

  # This version is called when a macro with arguments is defined for the first
  # time.
  defp update_macro_info(
    %MacroData{
      func_name: func_name,
    } = macro,
    is_redefined, _args, name, _replacement,
    %ModuleData{
      macros: macros,
      used_func_names: used_func_names
    } = module_data)
  do
    {func_name, used_func_names} = update_macro_name(name, func_name, used_func_names, "erlmacro")
    macro = %MacroData{macro |
      is_redefined: is_redefined,
      func_name: func_name
    }
    %ModuleData{module_data |
      macros: Map.put(macros, name, macro),
      used_func_names: used_func_names
    }
  end


  # Gien a macro replacement Erlang AST, return the constant expression if
  # recognized as such, or nil if not.

  defp extract_replacement_expr([[expr]]), do: expr
  defp extract_replacement_expr(_), do: nil


  # Choose an Elixir name for a macro.

  defp update_macro_name(given_name, nil, used_names, prefix) do
    macro_name = Utils.find_available_name(given_name, used_names, prefix)
    used_names = MapSet.put(used_names, macro_name)
    {macro_name, used_names}
  end
  defp update_macro_name(_given_name, cur_name, used_names, _prefix) do
    {cur_name, used_names}
  end


  # Update the requires_init value. Makes a change if the old value is nil,
  # otherwise keeps the old value.

  defp update_requires_init(nil, nval), do: nval
  defp update_requires_init(oval, _nval), do: oval


  # Update the state of is_redefined.

  defp update_is_redefined(true, _args), do: true
  defp update_is_redefined(set, args) when is_list(args) do
    update_is_redefined(set, Enum.count(args))
  end
  defp update_is_redefined(set, arity) do
    if MapSet.member?(set, arity), do: true, else: MapSet.put(set, arity)
  end

end
