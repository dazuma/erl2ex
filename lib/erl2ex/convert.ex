
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


  @auto_registered_attrs [:vsn, :compile, :on_load, :behaviour, :behavior]


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

    %ExAttr{
      name: mapped_name,
      tracking_name: tracking_name,
      arg: Expressions.conv_expr(context, replacement),
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

    %ExMacro{
      signature: {mapped_name, [], ex_args},
      tracking_name: tracking_name,
      stringifications: stringification_map,
      expr: Expressions.conv_expr(replacement_context, replacement),
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

    %ExRecord{
      tag: name,
      macro: Context.record_function_name(context, name),
      fields: Expressions.conv_list(context, fields),
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

    %ExType{
      kind: ex_kind,
      signature: {name, [], Expressions.conv_list(context, params)},
      defn: Expressions.conv_expr(context, defn),
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

  defp conv_var_mapped_spec_clause(context, name, {:type, _, :fun, [args, result]}), do:
    {:::, [], [{name, [], Expressions.conv_expr(context, args)}, Expressions.conv_expr(context, result)]}

  defp conv_var_mapped_spec_clause(context, name, {:type, _, :bounded_fun, [func, constraints]}), do:
    {:when, [], [conv_spec_clause(context, name, func), Enum.map(constraints, &(conv_spec_constraint(context, &1)))]}

  defp conv_spec_constraint(context, {:type, _, :constraint, [{:atom, _, :is_subtype}, [{:var, _, var}, type]]}), do:
    {Utils.lower_atom(var), Expressions.conv_expr(context, type)}


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
    ex_clause = %ExClause{
      signature: clause_signature(context, name, args, guards),
      exprs: Expressions.conv_list(context, exprs),
      comments: head_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
    {ex_clause, remaining_comments}
  end


  defp clause_signature(context, name, params, []), do:
    {name, [], Expressions.conv_list(context, params)}

  defp clause_signature(context, name, params, guards), do:
    {:when, [], [clause_signature(context, name, params, []), Expressions.guard_seq(context, guards, nil)]}


  defp line_range([], range), do:
    range

  defp line_range([val | rest], range), do:
    line_range(rest, line_range(val, range))

  defp line_range({_, line, val1}, range), do:
    line_range(val1, range |> add_range(line))

  defp line_range({_, line, _val1, val2}, range), do:
    line_range(val2, add_range(range, line))

  defp line_range({_, line, _val1, _val2, val3}, range), do:
    line_range(val3, add_range(range, line))

  defp line_range({_, line}, range), do:
    add_range(range, line)

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
