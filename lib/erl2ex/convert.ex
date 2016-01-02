
defmodule Erl2ex.Convert do

  @moduledoc false

  alias Erl2ex.ErlAttr
  alias Erl2ex.ErlDefine
  alias Erl2ex.ErlDirective
  alias Erl2ex.ErlFunc
  alias Erl2ex.ErlImport
  alias Erl2ex.ErlRecord
  alias Erl2ex.ErlSpec
  alias Erl2ex.ErlType

  alias Erl2ex.ExAttr
  alias Erl2ex.ExCallback
  alias Erl2ex.ExClause
  alias Erl2ex.ExDirective
  alias Erl2ex.ExFunc
  alias Erl2ex.ExImport
  alias Erl2ex.ExMacro
  alias Erl2ex.ExModule
  alias Erl2ex.ExRecord
  alias Erl2ex.ExType

  alias Erl2ex.Convert.Context
  alias Erl2ex.Convert.Expressions
  alias Erl2ex.Convert.Headers
  alias Erl2ex.Convert.Utils
  alias Erl2ex.Convert.VarRenamer


  @auto_registered_attrs [:vsn, :compile, :on_load, :behaviour, :behavior]


  def module(erl_module, opts \\ []) do
    context = Context.build(erl_module, opts)
    forms = erl_module.forms |> Enum.map(&(conv_form(context, &1)))
    forms = [Headers.build_header(context, forms) | forms]
    %ExModule{
      name: erl_module.name,
      comments: erl_module.comments |> convert_comments,
      forms: forms
    }
  end


  defp conv_form(context, %ErlFunc{name: name, arity: arity, clauses: clauses, comments: comments}) do
    mapped_name = Context.local_function_name(context, name)
    spec_info = Context.specs_for_func(context, name)
    is_exported = Context.is_exported?(context, name, arity)

    first_line = clauses |> List.first |> elem(1)
    {main_comments, clause_comments} = split_comments(comments, first_line)
    main_comments = spec_info.comments ++ main_comments

    {ex_clauses, _} = clauses
      |> Enum.map_reduce(clause_comments, &(conv_clause(context, &1, &2, mapped_name)))
    specs = spec_info.clauses
      |> Enum.map(&(conv_spec_clause(context, mapped_name, &1)))

    %ExFunc{
      name: mapped_name,
      arity: arity,
      public: is_exported,
      specs: specs,
      comments: main_comments |> convert_comments,
      clauses: ex_clauses
    }
  end

  defp conv_form(_context, %ErlImport{line: line, module: mod, funcs: funcs, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)

    %ExImport{
      module: mod,
      funcs: funcs,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(_context, %ErlAttr{name: name, line: line, arg: arg, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    {name, arg} = conv_attr(name, arg)
    register = not name in @auto_registered_attrs

    %ExAttr{
      name: name,
      register: register,
      arg: arg,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(context, %ErlDefine{line: line, name: name, args: nil, replacement: replacement, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    mapped_name = Context.macro_const_name(context, name)
    tracking_name = Context.tracking_attr_name(context, name)
    {ex_arg, _} = Expressions.conv_expr(replacement, context)

    %ExAttr{
      name: mapped_name,
      tracking_name: tracking_name,
      arg: ex_arg,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(context, %ErlDefine{line: line, name: name, args: args, replacement: replacement, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    {variable_map, stringification_map} = VarRenamer.compute_var_maps(replacement, args)

    replacement_context = context
      |> Context.set_variable_maps(variable_map, args, stringification_map)
    ex_args = args |> Enum.map(fn arg -> {Utils.lower_atom(arg), [], Elixir} end)
    mapped_name = Context.macro_function_name(context, name)
    tracking_name = Context.tracking_attr_name(context, name)
    {ex_expr, _} = Expressions.conv_expr(replacement, replacement_context)

    %ExMacro{
      signature: {mapped_name, [], ex_args},
      tracking_name: tracking_name,
      stringifications: stringification_map,
      expr: ex_expr,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(context, %ErlDirective{line: line, directive: directive, name: name, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    tracking_name = if name == nil do
      nil
    else
      Context.tracking_attr_name(context, name)
    end

    %ExDirective{
      directive: directive,
      name: tracking_name,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(context, %ErlRecord{line: line, name: name, fields: fields, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    {ex_fields, _} = Expressions.conv_list(fields, context)

    %ExRecord{
      tag: name,
      macro: Context.record_function_name(context, name),
      fields: ex_fields,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(context, %ErlType{line: line, kind: kind, name: name, params: params, defn: defn, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    {variable_map, _stringification_map} = VarRenamer.compute_var_maps([params, defn])
    context = context
      |> Context.set_variable_maps(variable_map, [], HashDict.new)

    ex_kind = cond do
      kind == :opaque ->
        :opaque
      Context.is_type_exported?(context, name, Enum.count(params)) ->
        :type
      true ->
        :typep
    end
    {ex_params, _} = Expressions.conv_list(params, context)
    {ex_defn, _} = Expressions.conv_expr(defn, context)

    %ExType{
      kind: ex_kind,
      signature: {name, [], ex_params},
      defn: ex_defn,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(context, %ErlSpec{line: line, name: name, clauses: clauses, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    specs = clauses |> Enum.map(&(conv_spec_clause(context, name, &1)))

    %ExCallback{
      name: name,
      specs: specs,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end


  defp conv_attr(:on_load, {name, 0}), do: {:on_load, name}
  defp conv_attr(:behavior, behaviour), do: {:behaviour, behaviour}
  defp conv_attr(attr, val), do: {attr, val}


  defp conv_spec_clause(context, name, clause) do
    {variable_map, _stringification_map} = VarRenamer.compute_var_maps(clause)
    context
      |> Context.set_variable_maps(variable_map, [], HashDict.new)
      |> conv_var_mapped_spec_clause(name, clause)
  end

  defp conv_var_mapped_spec_clause(context, name, {:type, _, :fun, [args, result]}) do
    {ex_args, _} = Expressions.conv_expr(args, context)
    {ex_result, _} = Expressions.conv_expr(result, context)
    {:::, [], [{name, [], ex_args}, ex_result]}
  end

  defp conv_var_mapped_spec_clause(context, name, {:type, _, :bounded_fun, [func, constraints]}) do
    {:when, [], [conv_spec_clause(context, name, func), Enum.map(constraints, &(conv_spec_constraint(context, name, &1)))]}
  end

  defp conv_var_mapped_spec_clause(context, name, expr), do:
    Utils.handle_error(context, expr, "in spec for #{name}")

  defp conv_spec_constraint(context, _name, {:type, _, :constraint, [{:atom, _, :is_subtype}, [{:var, _, var}, type]]}) do
    {ex_type, _} = Expressions.conv_expr(type, context)
    {Utils.lower_atom(var), ex_type}
  end

  defp conv_spec_constraint(context, name, expr), do:
    Utils.handle_error(context, expr, "in spec constraint for #{name}")


  defp conv_clause(context, clause, comments, name) do
    {variable_map, _stringification_map} = VarRenamer.compute_var_maps(clause)
    context
      |> Context.set_variable_maps(variable_map, [], HashDict.new)
      |> conv_var_mapped_clause(clause, comments, name)
  end

  defp conv_var_mapped_clause(context, {:clause, line, args, guards, exprs}, comments, name) do
    lines = line_range(exprs, line..line)
    {head_comments, comments} = split_comments(comments, lines.first)
    {inline_comments, remaining_comments} = split_comments(comments, lines.last)
    context = Context.push_scope(context)
    {ex_signature, context} = clause_signature(name, args, guards, context)
    {ex_exprs, _} = Expressions.conv_list(exprs, context)

    ex_clause = %ExClause{
      signature: ex_signature,
      exprs: ex_exprs,
      comments: head_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
    {ex_clause, remaining_comments}
  end


  defp clause_signature(name, params, [], context) do
    context = Context.push_match_level(context, true)
    {ex_params, context} = Expressions.conv_list(params, context)
    context = Context.pop_match_level(context)
    {{name, [], ex_params}, context}
  end

  defp clause_signature(name, params, guards, context) do
    {ex_guards, context} = Expressions.guard_seq(guards, context)
    {sig_without_guards, context} = clause_signature(name, params, [], context)
    {{:when, [], [sig_without_guards | ex_guards]}, context}
  end


  defp line_range([], range), do:
    range

  defp line_range([val | rest], range), do:
    line_range(rest, line_range(val, range))

  defp line_range({_, line, val1}, range) when is_integer(line), do:
    line_range(val1, range |> add_range(line))

  defp line_range({_, line, _val1, val2}, range) when is_integer(line), do:
    line_range(val2, add_range(range, line))

  defp line_range({_, line, _val1, _val2, val3}, range) when is_integer(line), do:
    line_range(val3, add_range(range, line))

  defp line_range({_, line}, range) when is_integer(line), do:
    add_range(range, line)

  defp line_range({_, list}, range) when is_list(list), do:
    line_range(list, range)

  defp line_range(_, range), do:
    range


  defp add_range(nil, line), do: line..line
  defp add_range(a.._b, line), do: a..line


  defp split_comments(comments, line), do:
    comments |> Enum.split_while(fn {:comment, ln, _} -> ln < line end)


  defp convert_comments(comments) do
    comments |> Enum.map(fn {:comment, _, str} ->
      Regex.replace(~r{^%}, to_string(str), "#")
    end)
  end

end
