
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
  alias Erl2ex.Pipeline.Utils


  @auto_registered_attrs [:vsn, :compile, :on_load, :behaviour, :behavior]


  def conv_form({:function, _line, name, arity, clauses}, context) do
    conv_function_form(name, arity, clauses, context)
  end

  def conv_form({:attribute, _line, attr_name, _}, context)
  when attr_name == :export or attr_name == :export_type or attr_name == :module or
      attr_name == :include or attr_name == :include_lib do
    {[], context}
  end

  def conv_form({:attribute, _line, :import, {modname, funcs}}, context) do
    conv_import_form(modname, funcs, context)
  end

  def conv_form({:attribute, _line, attr_name, {name, defn, params}}, context)
  when attr_name == :type or attr_name == :opaque do
    conv_type_form(attr_name, name, defn, params, context)
  end

  def conv_form({:attribute, _line, attr_name, {{name, _}, clauses}}, context)
  when attr_name == :spec or attr_name == :callback do
    conv_spec_form(attr_name, {}, name, clauses, context)
  end

  def conv_form({:attribute, _line, :spec, {{spec_mod, name, _}, clauses}}, context) do
    conv_spec_form(:spec, spec_mod, name, clauses, context)
  end

  def conv_form({:attribute, _line, :record, {recname, fields}}, context) do
    conv_record_form(recname, fields, context)
  end

  def conv_form({:attribute, _line, :file, {file, fline}}, context) do
    conv_file_form(file, fline, context)
  end

  def conv_form({:attribute, _line, attr_name}, context)
  when attr_name == :else or attr_name == :endif do
    conv_directive_form(attr_name, {}, context)
  end

  def conv_form({:attribute, _line, attr_name, arg}, context)
  when attr_name == :ifdef or attr_name == :ifndef or attr_name == :undef do
    conv_directive_form(attr_name, arg, context)
  end

  def conv_form({:attribute, _line, attr_name, arg}, context) do
    conv_attr_form(attr_name, arg, context)
  end

  def conv_form({:define, _line, macro, replacement}, context) do
    conv_define_form(macro, replacement, context)
  end

  def conv_form(erl_form, context) do
    line = if is_tuple(erl_form) and tuple_size(erl_form) >= 3, do: elem(erl_form, 1), else: :unknown
    raise CompileError,
      file: Context.cur_file_path_for_display(context),
      line: line,
      description: "Unrecognized Erlang form ast: #{inspect(erl_form)}"
  end


  defp conv_function_form(name, arity, clauses, context) do
    module_data = context.module_data
    mapped_name = ModuleData.local_function_name(module_data, name)
    is_exported = ModuleData.is_exported?(module_data, name, arity)
    func_renamer = if Names.deffable_function_name?(mapped_name) do
      nil
    else
      ModuleData.func_renamer_name(module_data)
    end
    ex_clauses = Enum.map(clauses, &(conv_clause(context, &1, mapped_name)))

    ex_func = %ExFunc{
      name: mapped_name,
      arity: arity,
      public: is_exported,
      func_renamer: func_renamer,
      clauses: ex_clauses
    }
    {[ex_func], context}
  end


  defp conv_import_form(modname, funcs, context) do
    ex_import = %ExImport{
      module: modname,
      funcs: funcs
    }
    {[ex_import], context}
  end


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


  defp conv_spec_form(attr_name, mod_name, name, clauses, context) do
    if mod_name == {} or mod_name == context.module_data.name do
      specs = clauses |> Enum.map(fn spec_clause ->
        {ex_spec, _} = conv_spec_clause(name, spec_clause, context)
        ex_spec
      end)
      ex_callback = %ExSpec{
        kind: attr_name,
        name: name,
        specs: specs
      }
      {[ex_callback], context}
    else
      {[], context}
    end
  end


  defp conv_spec_clause(name, {:type, _, :fun, [args, result]}, context) do
    conv_spec_clause_impl(name, args, result, [], context)
  end

  defp conv_spec_clause(name, {:type, _, :bounded_fun, [{:type, _, :fun, [args, result]}, constraints]}, context) do
    conv_spec_clause_impl(name, args, result, constraints, context)
  end

  defp conv_spec_clause(name, expr, context), do:
    Context.handle_error(context, expr, "in spec for #{name}")


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


  defp conv_spec_constraint(context, _name, {:type, _, :constraint, [{:atom, _, :is_subtype}, [{:var, _, var}, type]]}) do
    {ex_type, _} = ErlExpressions.conv_expr(type, context)
    {:normal_var, mapped_name, _, _} = Context.map_variable_name(context, var)
    {mapped_name, ex_type}
  end

  defp conv_spec_constraint(context, name, expr), do:
    Context.handle_error(context, expr, "in spec constraint for #{name}")


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


  defp conv_file_form(file, fline, context) do
    comment = convert_comments(["% File #{file |> List.to_string |> inspect} Line #{fline}"])
    ex_comment = %ExComment{comments: comment}
    {[ex_comment], context}
  end


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


  defp conv_attr(:on_load, {name, 0}), do: {:on_load, name}
  defp conv_attr(:behavior, behaviour), do: {:behaviour, behaviour}
  defp conv_attr(attr, val), do: {attr, val}


  defp conv_define_form(macro, replacement, context) do
    {name, args} = interpret_macro_expr(macro)
    arity = if args == nil, do: nil, else: Enum.count(args)
    if args == nil, do: args = []
    module_data = context.module_data
    needs_dispatch = ModuleData.macro_needs_dispatch?(module_data, name)
    ex_args = args |> Enum.map(fn arg -> {Utils.lower_atom(arg), [], Elixir} end)
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


  defp interpret_macro_expr({:call, _, name_expr, arg_exprs}) do
    name = interpret_macro_name(name_expr)
    args = arg_exprs |> Enum.map(fn {:var, _, n} -> n end)
    {name, args}
  end

  defp interpret_macro_expr(macro_expr) do
    name = interpret_macro_name(macro_expr)
    {name, nil}
  end


  defp interpret_macro_name({:var, _, name}), do: name
  defp interpret_macro_name({:atom, _, name}), do: name
  defp interpret_macro_name(name) when is_atom(name), do: name


  defp conv_clause(context, clause, name) do
    context
      |> Context.set_variable_maps(clause)
      |> conv_var_mapped_clause(clause, name)
  end

  defp conv_var_mapped_clause(context, {:clause, _line, args, guards, exprs}, name) do
    context = Context.push_scope(context)
    {ex_signature, context} = clause_signature(name, args, guards, context)
    {ex_exprs, _} = ErlExpressions.conv_list(exprs, context)

    %ExClause{
      signature: ex_signature,
      exprs: ex_exprs
    }
  end


  defp clause_signature(name, params, [], context) do
    context = Context.push_match_level(context, true)
    {ex_params, context} = ErlExpressions.conv_list(params, context)
    context = Context.pop_match_level(context)
    {{name, [], ex_params}, context}
  end

  defp clause_signature(name, params, guards, context) do
    {ex_guards, context} = ErlExpressions.guard_seq(guards, context)
    {sig_without_guards, context} = clause_signature(name, params, [], context)
    {{:when, [], [sig_without_guards | ex_guards]}, context}
  end


  defp convert_comments(comments) do
    comments |> Enum.map(fn
      {:comment, _, str} -> str |> List.to_string |> convert_comment_str
      str when is_binary(str) -> convert_comment_str(str)
    end)
  end

  defp convert_comment_str(str) do
    Regex.replace(~r{^%+}, str, fn prefix -> String.replace(prefix, "%", "#") end)
  end

end
