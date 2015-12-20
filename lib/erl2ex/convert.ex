
defmodule Erl2ex.Convert do

  alias Erl2ex.Convert.Context


  def module(erl_module, opts \\ []) do
    context = Context.build(erl_module, opts)
    %Erl2ex.ExModule{
      name: erl_module.name,
      comments: erl_module.comments |> convert_comments,
      forms: erl_module.forms |> Enum.map(&(formp(context, &1)))
    }
  end


  def form(form, module, opts \\ []) do
    formp(Context.build(module, opts), form)
  end


  def expression(exp, opts \\ []) do
    expr(Context.build(opts), exp)
  end


  @import_kernel_metadata [context: Elixir, import: Kernel]
  @import_bitwise_metadata [context: Elixir, import: Bitwise]

  @op_map [
    ==: {@import_kernel_metadata, :==},
    "/=": {@import_kernel_metadata, :!=},
    "=<": {@import_kernel_metadata, :<=},
    >=: {@import_kernel_metadata, :>=},
    <: {@import_kernel_metadata, :<},
    >: {@import_kernel_metadata, :>},
    "=:=": {@import_kernel_metadata, :===},
    "=/=": {@import_kernel_metadata, :!==},
    +: {@import_kernel_metadata, :+},
    -: {@import_kernel_metadata, :-},
    *: {@import_kernel_metadata, :*},
    /: {@import_kernel_metadata, :/},
    div: {@import_kernel_metadata, :div},
    rem: {@import_kernel_metadata, :rem},
    not: {@import_kernel_metadata, :not},
    orelse: {@import_kernel_metadata, :or},
    andalso: {@import_kernel_metadata, :and},
    # TODO: Figure out or, and, xor, which might be non-short-circuiting
    ++: {@import_kernel_metadata, :++},
    --: {@import_kernel_metadata, :--},
    !: {@import_kernel_metadata, :send},
    band: {@import_bitwise_metadata, :&&&},
    bor: {@import_bitwise_metadata, :|||},
    bxor: {@import_bitwise_metadata, :^^^},
    bsl: {@import_bitwise_metadata, :<<<},
    bsr: {@import_bitwise_metadata, :>>>},
    bnot: {@import_bitwise_metadata, :~~~},
  ] |> Enum.into(HashDict.new)

  @autoimport_map [
    abs: :abs,
    bit_size: :bit_size,
    byte_size: :byte_size,
    is_atom: :is_atom
  ] |> Enum.into(HashDict.new)


  defp formp(context, %Erl2ex.ErlFunc{name: name, arity: arity, clauses: clauses, comments: comments}) do
    mapped_name = Context.local_function_name(context, name)
    is_exported = Context.is_exported?(context, name, arity)
    first_line = clauses |> List.first |> elem(1)
    {main_comments, clause_comments} = split_comments(comments, first_line)
    {ex_clauses, _} = clauses
      |> Enum.map_reduce(clause_comments, &(clause(context, &1, &2, mapped_name)))

    %Erl2ex.ExFunc{
      name: mapped_name,
      arity: arity,
      public: is_exported,
      comments: main_comments |> convert_comments,
      clauses: ex_clauses
    }
  end

  defp formp(_context, %Erl2ex.ErlImport{line: line, module: module, funcs: funcs, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)

    %Erl2ex.ExImport{
      module: module,
      funcs: funcs,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp formp(_context, %Erl2ex.ErlAttr{name: name, line: line, arg: arg, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)

    %Erl2ex.ExAttr{
      name: name,
      arg: arg,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp formp(context, %Erl2ex.ErlDefine{line: line, name: name, args: nil, replacement: replacement, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    mapped_name = Context.macro_const_name(context, name)
    tracking_name = Context.tracking_attr_name(context, name)

    %Erl2ex.ExAttr{
      name: mapped_name,
      tracking_name: tracking_name,
      arg: expr(context, replacement),
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp formp(context, %Erl2ex.ErlDefine{line: line, name: name, args: args, replacement: replacement, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)

    replacement_context = %Context{context | quoted_variables: args}
    ex_args = args |> Enum.map(fn arg -> {lower_atom(arg), [], Elixir} end)
    mapped_name = Context.macro_function_name(context, name)
    tracking_name = Context.tracking_attr_name(context, name)

    %Erl2ex.ExMacro{
      signature: {mapped_name, [], ex_args},
      tracking_name: tracking_name,
      expr: expr(replacement_context, replacement),
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp formp(context, %Erl2ex.ErlDirective{line: line, directive: directive, name: name, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    tracking_name = if name == nil do
      nil
    else
      Context.tracking_attr_name(context, name)
    end

    %Erl2ex.ExDirective{
      directive: directive,
      name: tracking_name,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end


  # Expression rules

  defp expr(_context, {:atom, _, val}) when is_atom(val), do:
    val

  defp expr(_context, {:integer, _, val}) when is_integer(val), do:
    val

  defp expr(_context, {:char, _, val}) when is_integer(val), do:
    val

  defp expr(_context, {:float, _, val}) when is_float(val), do:
    val

  defp expr(context, {:tuple, _, [val1, val2]}), do:
    {expr(context, val1), expr(context, val2)}

  defp expr(context, {:tuple, _, vals}) when is_list(vals), do:
    {:{}, [], vals |> Enum.map(&(expr(context, &1)))}

  defp expr(_context, {nil, _}), do:
    []

  defp expr(context, {:cons, _, head, tail}), do:
    [expr(context, head) | expr(context, tail)]

  # TODO: binary literal
  # TODO: map literal

  defp expr(context, {:var, _, name}) when is_atom(name), do:
    generalized_var(context, name, Atom.to_string(name))

  defp expr(context, {:match, _, lhs, rhs}), do:
    {:=, [], [expr(context, lhs), expr(context, rhs)]}

  defp expr(context, {:remote, _, mod, func}), do:
    {:., [], [expr(context, mod), expr(context, func)]}

  defp expr(context, {:call, _, func, args}) when is_list(args), do:
    {func_spec(context, func, args), [], list(context, args)}

  defp expr(context, {:op, _, op, arg}) do
    {metadata, ex_op} = Dict.fetch!(@op_map, op)
    {ex_op, metadata, [expr(context, arg)]}
  end

  defp expr(context, {:op, _, op, arg1, arg2}) do
    {metadata, ex_op} = Dict.fetch!(@op_map, op)
    {ex_op, metadata, [expr(context, arg1), expr(context, arg2)]}
  end

  defp expr(context, {:clause, _, [], guards, arg}), do:
    {:"->", [], [[guard_seq(context, guards, nil)], block(context, arg)]}

  defp expr(context, {:clause, _, params, [], arg}), do:
    {:"->", [], [list(context, params), block(context, arg)]}

  defp expr(context, {:clause, _, params, guards, arg}), do:
    {:"->", [], [[{:when, [], list(context, params) ++ [guard_seq(context, guards, nil)]}], block(context, arg)]}

  defp expr(context, {:case, _, val, clauses}) when is_list(clauses), do:
    {:case, [], [expr(context, val), [do: list(context, clauses)]]}

  defp expr(context, {:if, _, clauses}) when is_list(clauses), do:
    {:cond, [], [[do: list(context, clauses)]]}

  defp expr(context, {:receive, _, clauses}) when is_list(clauses), do:
    {:receive, [], [[do: list(context, clauses)]]}

  defp expr(context, {:fun, _, {:clauses, clauses}}) when is_list(clauses), do:
    {:fn, [], list(context, clauses)}

  defp expr(context, {:block, _, arg}) when is_list(arg), do:
    block(context, arg)

  defp expr(context, {:generate, _, into, arg}), do:
    {:<-, [], [expr(context, into), expr(context, arg)]}

  defp expr(context, {:lc, _, expression, qualifiers}), do:
    {:for, [], list(context, qualifiers) ++ [[do: expr(context, expression)]]}

  defp expr(context, {:map_field_assoc, _, lhs, rhs}), do:
    {expr(context, lhs), expr(context, rhs)}

  defp expr(context, {:map_field_exact, _, lhs, rhs}), do:
    {expr(context, lhs), expr(context, rhs)}

  defp expr(context, {:map, _, associations}), do:
    {:%{}, [], list(context, associations)}

  defp expr(context, {:map, _, associations}), do:
    {:%{}, [], list(context, associations)}

  defp expr(context, {:map, _, base_map, []}), do:
    expr(context, base_map)

  defp expr(context, {:map, _, base_map, assocs}), do:
    update_map(context, expr(context, base_map), assocs)


  defp update_map(context, base_map, assocs = [{:map_field_exact, _, _, _} | _]) do
    {exact_assocs, remaining_assocs} = assocs
      |> Enum.split_while(fn
        {:map_field_exact, _, _, _} -> true
        _ -> false
      end)
    new_base = {:%{}, [], [{:|, [], [base_map, list(context, exact_assocs)]}]}
    update_map(context, new_base, remaining_assocs)
  end

  defp update_map(context, base_map, assocs = [{:map_field_assoc, _, _, _} | _]) do
    {inexact_assocs, remaining_assocs} = assocs
      |> Enum.split_while(fn
        {:map_field_assoc, _, _, _} -> true
        _ -> false
      end)
    new_base = {
      {:., [], [{:__aliases__, [alias: false], [:Map]}, :merge]},
      [],
      [base_map, {:%{}, [], list(context, inexact_assocs)}]
    }
    update_map(context, new_base, remaining_assocs)
  end

  defp update_map(_context, base_map, []), do: base_map


  defp generalized_var(context, _atom_name, << "?" :: utf8, name :: binary >>) do
    macro_name = Context.macro_const_name(context, String.to_atom(name))
    {:@, @import_kernel_metadata, [{macro_name, [], Elixir}]}
  end

  defp generalized_var(context, atom_name, str_name) do
    var = {str_name |> lower_str |> String.to_atom, [], Elixir}
    if Context.is_quoted_var?(context, atom_name) do
      {:unquote, [], [var]}
    else
      var
    end
  end


  defp func_spec(context, func = {:remote, _, _, _}, _args), do:
    expr(context, func)

  defp func_spec(context, {:atom, _, func}, args) do
    arity = Enum.count(args)
    if Context.is_local_func?(context, func, arity) do
      Context.local_function_name(context, func)
    else
      case Dict.get(@autoimport_map, func, nil) do
        nil -> {:., [], [:erlang, func]}
        ex_name -> ex_name
      end
    end
  end

  defp func_spec(context, func = {:var, _, name}, _args) do
    case Atom.to_string(name) do
      << "?" :: utf8, basename :: binary >> ->
        Context.macro_function_name(context, String.to_atom(basename))
      _ ->
        {:., [], [expr(context, func)]}
    end
  end

  defp func_spec(context, func, _args), do:
    {:., [], [expr(context, func)]}


  defp block(context, [arg]), do:
    expr(context, arg)

  defp block(context, arg) when is_list(arg), do:
    {:__block__, [], list(context, arg)}


  defp list(context, list) when is_list(list), do:
    list |> Enum.map(&(expr(context, &1)))


  defp clause(context, {:clause, line, args, guards, exprs}, comments, name) do
    lines = line_range(exprs, line..line)
    {head_comments, comments} = split_comments(comments, lines.first)
    {inline_comments, remaining_comments} = split_comments(comments, lines.last)
    ex_clause = %Erl2ex.ExClause{
      signature: clause_signature(context, name, args, guards),
      exprs: list(context, exprs),
      comments: head_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
    {ex_clause, remaining_comments}
  end


  defp clause_signature(context, name, params, []), do:
    {name, [], list(context, params)}

  defp clause_signature(context, name, params, guards), do:
    {:when, [], [clause_signature(context, name, params, []), guard_seq(context, guards, nil)]}


  # Guard rules

  defp guard_seq(_context, [], result), do:
    result

  defp guard_seq(context, [ghead | gtail], result), do:
    guard_seq(context, gtail, guard_combine(result, guard_elem(context, ghead, nil), :or))


  defp guard_elem(_context, [], result), do:
    result

  defp guard_elem(context, [ghead | gtail], result), do:
    # TODO: Make sure we can get away with expr. Erlang guards can conceivably
    # resolve to a value other than true or false, which for Erlang should
    # fail the guard, but in Elixir will succeed the guard. If this is a
    # problem, the Elixir version might need to compare === true.
    guard_elem(context, gtail, guard_combine(result, expr(context, ghead), :and))


  defp guard_combine(nil, rhs, _op), do:
    rhs

  defp guard_combine(lhs, rhs, op), do:
    {op, @import_kernel_metadata, [lhs, rhs]}


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


  defp lower_str(<< first :: utf8, rest :: binary >>) do
    << String.downcase(<< first >>) :: binary, rest :: binary >>
  end

  defp lower_atom(atom) do
    atom |> Atom.to_string |> lower_str |> String.to_atom
  end


  defp split_comments(comments, line) do
    comments |> Enum.split_while(fn {:comment, ln, _} -> ln < line end)
  end


  defp convert_comments(comments) do
    comments |> Enum.map(fn {:comment, _, str} ->
      Regex.replace(~r{^%}, to_string(str), "#")
    end)
  end

end
