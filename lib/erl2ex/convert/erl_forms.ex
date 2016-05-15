# Conversion logic for standard (erlparse) AST forms.

defmodule Erl2ex.Convert.ErlForms do

  @moduledoc false


  alias Erl2ex.Pipeline.ExAttr
  alias Erl2ex.Pipeline.ExClause
  alias Erl2ex.Pipeline.ExComment
  alias Erl2ex.Pipeline.ExDirective
  alias Erl2ex.Pipeline.ExFunc
  alias Erl2ex.Pipeline.ExImport
  alias Erl2ex.Pipeline.ExMacro
  alias Erl2ex.Pipeline.ExRecord
  alias Erl2ex.Pipeline.ExSpec
  alias Erl2ex.Pipeline.ExType

  alias Erl2ex.Convert.Context
  alias Erl2ex.Convert.ErlExpressions

  alias Erl2ex.Pipeline.ModuleData
  alias Erl2ex.Pipeline.Names


  # A list of attributes that are automatically registered in Elixir and
  # do not need to be registered explicitly.
  @auto_registered_attrs [:vsn, :compile, :on_load, :behaviour, :behavior]


  # A dispatching function that converts a form with a context. Returns a
  # tuple of a list (possibly empty) of ex_data forms, and an updated context.

  # Handler for function definitions.
  def conv_form({:function, _line, name, arity, clauses}, context) do
    conv_function_form(name, arity, clauses, context)
  end

  # Handler for attribute definitions that are ignored by the converter because
  # they are fully handled by earlier phases.
  def conv_form({:attribute, _line, attr_name, _}, context)
  when attr_name == :export or attr_name == :export_type or attr_name == :module or
      attr_name == :include or attr_name == :include_lib do
    {[], context}
  end

  # Handler for import directives.
  def conv_form({:attribute, _line, :import, {modname, funcs}}, context) do
    conv_import_form(modname, funcs, context)
  end

  # Handler for type definition directives.
  def conv_form({:attribute, _line, attr_name, {name, defn, params}}, context)
  when attr_name == :type or attr_name == :opaque do
    conv_type_form(attr_name, name, defn, params, context)
  end

  # Handler for local function specification directives.
  def conv_form({:attribute, _line, attr_name, {{name, _}, clauses}}, context)
  when attr_name == :spec or attr_name == :callback do
    conv_spec_form(attr_name, {}, name, clauses, context)
  end

  # Handler for remote function specification directives.
  def conv_form({:attribute, _line, :spec, {{spec_mod, name, _}, clauses}}, context) do
    conv_spec_form(:spec, spec_mod, name, clauses, context)
  end

  # Handler for record definition directives.
  def conv_form({:attribute, _line, :record, {recname, fields}}, context) do
    conv_record_form(recname, fields, context)
  end

  # Handler for file/line state directives.
  def conv_form({:attribute, _line, :file, {file, fline}}, context) do
    conv_file_form(file, fline, context)
  end

  # Handler for file/line state directives.
  def conv_form({:attribute, _line, :compile, arg}, context) do
    conv_compile_directive_form(arg, context)
  end

  # Handler for "else" and "endif" directives (i.e. with no arguments)
  def conv_form({:attribute, _line, attr_name}, context)
  when attr_name == :else or attr_name == :endif do
    conv_directive_form(attr_name, {}, context)
  end

  # Handler for "ifdef", "ifndef", and "undef" directives (i.e. with one argument)
  def conv_form({:attribute, _line, attr_name, arg}, context)
  when attr_name == :ifdef or attr_name == :ifndef or attr_name == :undef do
    conv_directive_form(attr_name, arg, context)
  end

  # Handler for attributes not otherwise recognized as special.
  def conv_form({:attribute, _line, attr_name, arg}, context) do
    conv_attr_form(attr_name, arg, context)
  end

  # Handler for Erlang macro definitions.
  def conv_form({:define, _line, macro, replacement}, context) do
    conv_define_form(macro, replacement, context)
  end

  # Fall-through handler that throws an error for unrecognized form type.
  def conv_form(erl_form, context) do
    line = if is_tuple(erl_form) and tuple_size(erl_form) >= 3, do: elem(erl_form, 1), else: :unknown
    raise CompileError,
      file: Context.cur_file_path_for_display(context),
      line: line,
      description: "Unrecognized Erlang form ast: #{inspect(erl_form)}"
  end


  #### Converts the given function.

  defp conv_function_form(name, arity, clauses, context) do
    module_data = context.module_data
    mapped_name = ModuleData.local_function_name(module_data, name)
    is_exported = ModuleData.is_exported?(module_data, name, arity)
    ex_clauses = Enum.map(clauses, &(conv_clause(context, &1, mapped_name)))

    ex_func = %ExFunc{
      name: mapped_name,
      arity: arity,
      public: is_exported,
      clauses: ex_clauses
    }
    {[ex_func], context}
  end


  # Converts a single clause in a function definition

  defp conv_clause(context, {:clause, _line, args, guards, exprs} = clause, name) do
    context = context
      |> Context.set_variable_maps(clause)
      |> Context.push_scope()
    {ex_signature, context} = clause_signature(name, args, guards, context)
    {ex_exprs, _} = ErlExpressions.conv_list(exprs, context)

    %ExClause{
      signature: ex_signature,
      exprs: ex_exprs
    }
  end


  # Converts the signature in a function clause.

  # This function handle the case without guards
  defp clause_signature(name, params, [], context) do
    context = Context.push_match_level(context, true)
    {ex_params, context} = ErlExpressions.conv_list(params, context)
    context = Context.pop_match_level(context)
    if not Names.deffable_function_name?(name) do
      name = {:unquote, [], [name]}
    end
    {{name, [], ex_params}, context}
  end

  # This function handle the case with guards
  defp clause_signature(name, params, guards, context) do
    {ex_guards, context} = ErlExpressions.guard_seq(guards, context)
    {sig_without_guards, context} = clause_signature(name, params, [], context)
    {{:when, [], [sig_without_guards | ex_guards]}, context}
  end


  #### Converts the given import directive.

  defp conv_import_form(modname, funcs, context) do
    ex_import = %ExImport{
      module: modname,
      funcs: funcs
    }
    {[ex_import], context}
  end


  #### Converts the given type definition directive.

  defp conv_type_form(attr_name, name, defn, params, context) do
    ex_kind = cond do
      attr_name == :opaque ->
        :opaque
      ModuleData.is_type_exported?(context.module_data, name, Enum.count(params)) ->
        :type
      true ->
        :typep
    end

    type_context = context
      |> Context.set_variable_maps(params)
      |> Context.set_type_expr_mode()
    {ex_params, _} = ErlExpressions.conv_list(params, type_context)
    {ex_defn, _} = ErlExpressions.conv_expr(defn, type_context)

    ex_type = %ExType{
      kind: ex_kind,
      signature: {name, [], ex_params},
      defn: ex_defn
    }
    {[ex_type], context}
  end


  #### Converts the given function specification directive.
  # The mod_name argument is nil if local, or the module if remote.
  # For a remote function, emits something only if the module matches the
  # current module being defined.
  # Breaks the spec into clauses and calls conv_spec_clause on each.

  defp conv_spec_form(attr_name, mod_name, name, clauses, context) do
    if mod_name == {} or mod_name == context.module_data.name do
      if ModuleData.has_local_function_name?(context.module_data, name) do
        name = ModuleData.local_function_name(context.module_data, name)
      end
      specs = clauses |> Enum.map(fn spec_clause ->
        {ex_spec_expr, _} = conv_spec_clause(name, spec_clause, context)
        ex_spec_expr
      end)
      ex_spec = %ExSpec{
        kind: attr_name,
        name: name,
        specs: specs
      }
      {[ex_spec], context}
    else
      {[], context}
    end
  end


  # Converts a function specification clause without guards
  defp conv_spec_clause(name, {:type, _, :fun, [args, result]}, context) do
    conv_spec_clause_impl(name, args, result, [], context)
  end

  # Converts a function specification clause with guards
  defp conv_spec_clause(name, {:type, _, :bounded_fun, [{:type, _, :fun, [args, result]}, constraints]}, context) do
    conv_spec_clause_impl(name, args, result, constraints, context)
  end

  defp conv_spec_clause(name, expr, context), do:
    Context.handle_error(context, expr, "in spec for #{name}")


  # Convert a single function specification clause.

  defp conv_spec_clause_impl(name, args, result, constraints, context) do
    context = context
      |> Context.set_type_expr_mode()
      |> Context.set_variable_maps([args, result, constraints])

    {ex_args, context} = ErlExpressions.conv_expr(args, context)
    {ex_result, context} = ErlExpressions.conv_expr(result, context)
    ex_expr = {:::, [], [{name, [], ex_args}, ex_result]}

    ex_constraints = Enum.map(constraints, &(conv_spec_constraint(context, name, &1)))
    ex_constraints = context
      |> Context.get_variable_map()
      |> Map.values()
      |> Enum.sort()
      |> Enum.reduce(ex_constraints, fn mapped_var, cur_constraints ->
        if Keyword.has_key?(cur_constraints, mapped_var) do
          cur_constraints
        else
          cur_constraints ++ [{mapped_var, {:any, [], []}}]
        end
      end)

    if not Enum.empty?(ex_constraints) do
      ex_expr = {:when, [], [ex_expr, ex_constraints]}
    end
    {ex_expr, context}
  end


  # Convert a single constraint in a function specification

  defp conv_spec_constraint(context, _name, {:type, _, :constraint, [{:atom, _, :is_subtype}, [{:var, _, var}, type]]}) do
    {ex_type, _} = ErlExpressions.conv_expr(type, context)
    {:normal_var, mapped_name, _, _} = Context.map_variable_name(context, var)
    {mapped_name, ex_type}
  end

  defp conv_spec_constraint(context, name, expr), do:
    Context.handle_error(context, expr, "in spec constraint for #{name}")


  #### Converts the given record definition directive.

  defp conv_record_form(recname, fields, context) do
    context = Context.start_record_types(context)
    {ex_fields, context} = ErlExpressions.conv_record_def_list(fields, context)
    context = Context.finish_record_types(context, recname)

    ex_record = %ExRecord{
      tag: recname,
      macro: ModuleData.record_function_name(context.module_data, recname),
      data_attr: ModuleData.record_data_attr_name(context.module_data, recname),
      fields: ex_fields
    }
    {[ex_record], context}
  end


  #### Converts the given file/line state directive.

  defp conv_file_form(file, fline, context) do
    comment = convert_comments(["% File #{file |> List.to_string |> inspect} Line #{fline}"])
    ex_comment = %ExComment{comments: comment}
    {[ex_comment], context}
  end


  # Given a list of comment data, returns a list of Elixir comment strings.

  defp convert_comments(comments) do
    comments |> Enum.map(fn
      {:comment, _, str} -> str |> List.to_string |> convert_comment_str
      str when is_binary(str) -> convert_comment_str(str)
    end)
  end


  # Coverts an Erlang comment string to an Elixir comment string. i.e.
  # it changes the % delimiter to #.

  defp convert_comment_str(str) do
    Regex.replace(~r{^%+}, str, fn prefix -> String.replace(prefix, "%", "#") end)
  end


  #### Converts the given preprocessor control directive.

  defp conv_directive_form(directive, name, context) do
    tracking_name = if name == {} do
      nil
    else
      ModuleData.tracking_attr_name(context.module_data, interpret_macro_name(name))
    end

    ex_directive = %ExDirective{
      directive: directive,
      name: tracking_name
    }
    {[ex_directive], context}
  end


  #### Converts the given compile options directive.

  defp conv_compile_directive_form(args, context) do
    conv_attr_form(:compile, conv_compile_option(args, context), context)
  end


  # Checks compile options. For inline options, maps the function name.

  defp conv_compile_option(options, context) when is_list(options) do
    options |> Enum.map(&(conv_compile_option(&1, context)))
  end

  defp conv_compile_option({:inline, {name, arity}}, context) do
    mapped_name = ModuleData.local_function_name(context.module_data, name)
    {:inline, {mapped_name, arity}}
  end

  defp conv_compile_option({:inline, funcs}, context) when is_list(funcs) do
    module_data = context.module_data
    mapped_funcs = funcs
      |> Enum.map(fn {name, arity} ->
        {ModuleData.local_function_name(module_data, name), arity}
      end)
    {:inline, mapped_funcs}
  end

  defp conv_compile_option(option, _context) do
    option
  end


  #### Converts the given attribute definition directive.

  defp conv_attr_form(name, arg, context) do
    {name, arg} = conv_attr(name, arg)
    register = not name in @auto_registered_attrs

    ex_attr = %ExAttr{
      name: name,
      register: register,
      arg: arg
    }
    {[ex_attr], context}
  end


  # Maps a few well-known attributes to Elixir equivalents.

  defp conv_attr(:on_load, {name, 0}), do: {:on_load, name}
  defp conv_attr(:behavior, behaviour), do: {:behaviour, behaviour}
  defp conv_attr(attr, val), do: {attr, val}


  #### Converts the given macro definition directive.

  defp conv_define_form(macro, replacement, context) do
    {name, args} = interpret_macro_expr(macro)
    arity = if args == nil, do: nil, else: Enum.count(args)
    if args == nil, do: args = []
    module_data = context.module_data
    needs_dispatch = ModuleData.macro_needs_dispatch?(module_data, name)
    macro_name = ModuleData.macro_function_name(module_data, name, arity)
    mapped_name = macro_name
    dispatch_name = nil
    if needs_dispatch do
      {mapped_name, context} = Context.generate_macro_name(context, name, arity)
      dispatch_name = macro_name
    end
    tracking_name = ModuleData.tracking_attr_name(module_data, name)

    context = context
      |> Context.set_variable_maps(replacement, args)
      |> Context.push_scope
      |> Context.start_macro_export_collection(args)

    variable_map = Context.get_variable_map(context)
    ex_args = args
      |> Enum.map(fn arg ->
        {Map.fetch!(variable_map, arg), [], Elixir}
      end)

    {normal_expr, guard_expr, context} = ErlExpressions.conv_macro_expr(replacement, context)
    ex_macro = %ExMacro{
      macro_name: mapped_name,
      signature: {mapped_name, [], ex_args},
      tracking_name: tracking_name,
      dispatch_name: dispatch_name,
      stringifications: context.stringification_map,
      expr: normal_expr,
      guard_expr: guard_expr
    }
    context = context
      |> Context.finish_macro_export_collection(name, arity)
      |> Context.pop_scope
      |> Context.clear_variable_maps

    {[ex_macro], context}
  end


  # Interprets the macro call sequence.

  defp interpret_macro_expr({:call, _, name_expr, arg_exprs}) do
    name = interpret_macro_name(name_expr)
    args = arg_exprs |> Enum.map(fn {:var, _, n} -> n end)
    {name, args}
  end

  defp interpret_macro_expr(macro_expr) do
    name = interpret_macro_name(macro_expr)
    {name, nil}
  end


  # Interprets a macro name. It may be a var or atom in the parse tree because
  # it may be capitalized or not.

  defp interpret_macro_name({:var, _, name}), do: name
  defp interpret_macro_name({:atom, _, name}), do: name
  defp interpret_macro_name(name) when is_atom(name), do: name

end
