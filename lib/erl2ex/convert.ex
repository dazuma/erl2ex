
defmodule Erl2ex.Convert do

  @import_kernel_context [context: Elixir, import: Kernel]
  @import_bitwise_context [context: Elixir, import: Bitwise]

  @op_map [
    ==: {@import_kernel_context, :==},
    "/=": {@import_kernel_context, :!=},
    "=<": {@import_kernel_context, :<=},
    >=: {@import_kernel_context, :>=},
    <: {@import_kernel_context, :<},
    >: {@import_kernel_context, :>},
    "=:=": {@import_kernel_context, :===},
    "=/=": {@import_kernel_context, :!==},
    +: {@import_kernel_context, :+},
    -: {@import_kernel_context, :-},
    *: {@import_kernel_context, :*},
    /: {@import_kernel_context, :/},
    div: {@import_kernel_context, :div},
    rem: {@import_kernel_context, :rem},
    not: {@import_kernel_context, :not},
    orelse: {@import_kernel_context, :or},
    andalso: {@import_kernel_context, :and},
    # TODO: Figure out or, and, xor, which might be non-short-circuiting
    ++: {@import_kernel_context, :++},
    --: {@import_kernel_context, :--},
    !: {@import_kernel_context, :send},
    band: {@import_bitwise_context, :&&&},
    bor: {@import_bitwise_context, :|||},
    bxor: {@import_bitwise_context, :^^^},
    bsl: {@import_bitwise_context, :<<<},
    bsr: {@import_bitwise_context, :>>>},
    bnot: {@import_bitwise_context, :~~~},
  ] |> Enum.into(HashDict.new)


  def module(erl_module, _opts \\ []) do
    %Erl2ex.ExModule{
      name: erl_module.name,
      comments: erl_module.comments |> convert_comments,
      forms: erl_module.forms |> Enum.map(&(form(&1, erl_module)))
    }
  end


  def form(%Erl2ex.ErlFunc{name: name, arity: arity, clauses: clauses, comments: comments}, erl_module) do
    first_line = clauses |> List.first |> elem(1)
    {main_comments, clause_comments} = split_comments(comments, first_line)
    {ex_clauses, _} = clauses
      |> Enum.map_reduce(clause_comments, &(clause(&1, &2, name)))

    %Erl2ex.ExFunc{
      name: name,
      arity: arity,
      public: Enum.member?(erl_module.exports, {name, arity}),
      comments: main_comments |> convert_comments,
      clauses: ex_clauses
    }
  end

  def form(%Erl2ex.ErlAttr{name: name, line: line, arg: arg, comments: comments}, _erl_module) do
    {main_comments, inline_comments} = split_comments(comments, line)

    %Erl2ex.ExAttr{
      name: name,
      arg: arg,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end


  # Expression rules

  def expr({:atom, _, val}) when is_atom(val), do:
    val

  def expr({:integer, _, val}) when is_integer(val), do:
    val

  def expr({:char, _, val}) when is_integer(val), do:
    val

  def expr({:float, _, val}) when is_float(val), do:
    val

  def expr({:tuple, _, [val1, val2]}), do:
    {expr(val1), expr(val2)}

  def expr({:tuple, _, vals}) when is_list(vals), do:
    {:{}, [], vals |> Enum.map(&expr/1)}

  def expr({nil, _}), do:
    []

  def expr({:cons, _, head, tail}), do:
    [expr(head) | expr(tail)]

  # TODO: binary literal
  # TODO: map literal

  def expr({:var, _, name}) when is_atom(name), do:
    {lower_atom(name), [], Elixir}

  def expr({:match, _, lhs, rhs}), do:
    {:=, [], [expr(lhs), expr(rhs)]}

  def expr({:remote, _, mod, func}), do:
    {:., [], [expr(mod), expr(func)]}

  def expr({:call, _, func, args}) when is_list(args), do:
    {expr(func), [], list(args)}

  def expr({:op, _, op, arg}) do
    {context, ex_op} = Dict.fetch!(@op_map, op)
    {ex_op, context, [expr(arg)]}
  end

  def expr({:op, _, op, arg1, arg2}) do
    {context, ex_op} = Dict.fetch!(@op_map, op)
    {ex_op, context, [expr(arg1), expr(arg2)]}
  end

  def expr({:clause, _, [], guards, arg}), do:
    {:"->", [], [[guard_seq(guards, nil)], block(arg)]}

  def expr({:clause, _, params, [], arg}), do:
    {:"->", [], [list(params), block(arg)]}

  def expr({:clause, _, params, guards, arg}), do:
    {:"->", [], [[{:when, [], list(params) ++ [guard_seq(guards, nil)]}], block(arg)]}

  def expr({:case, _, val, clauses}) when is_list(clauses), do:
    {:case, [], [expr(val), [do: list(clauses)]]}

  def expr({:if, _, clauses}) when is_list(clauses), do:
    {:cond, [], [[do: list(clauses)]]}

  def expr({:receive, _, clauses}) when is_list(clauses), do:
    {:receive, [], [[do: list(clauses)]]}


  def block([arg]), do:
    expr(arg)

  def block(arg) when is_list(arg), do:
    {:__block__, [], list(arg)}


  defp list(list) when is_list(list), do:
    list |> Enum.map(&expr/1)


  defp clause({:clause, line, args, guards, exprs}, comments, name) do
    lines = line_range(exprs, line..line)
    {head_comments, comments} = split_comments(comments, lines.first)
    {inline_comments, remaining_comments} = split_comments(comments, lines.last)
    ex_clause = %Erl2ex.ExClause{
      signature: clause_signature(name, args, guards),
      exprs: list(exprs),
      comments: head_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
    {ex_clause, remaining_comments}
  end


  defp clause_signature(name, params, []), do:
    {name, [], list(params)}

  defp clause_signature(name, params, guards), do:
    {:when, [], [clause_signature(name, params, []), guard_seq(guards, nil)]}


  # Guard rules

  defp guard_seq([], result), do:
    result

  defp guard_seq([ghead | gtail], result), do:
    guard_seq(gtail, guard_combine(result, guard_elem(ghead, nil), :or))


  defp guard_elem([], result), do:
    result

  defp guard_elem([ghead | gtail], result), do:
    # TODO: Make sure we can get away with expr. Erlang guards can conceivably
    # resolve to a value other than true or false, which for Erlang should
    # fail the guard, but in Elixir will succeed the guard. If this is a
    # problem, the Elixir version might need to compare === true.
    guard_elem(gtail, guard_combine(result, expr(ghead), :and))


  defp guard_combine(nil, rhs, _op), do:
    rhs

  defp guard_combine(lhs, rhs, op), do:
    {op, @import_kernel_context, [lhs, rhs]}


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


  defp lower_bin(<< first :: utf8, rest :: binary >>) do
    << String.downcase(<< first >>) :: binary, rest :: binary >>
  end

  defp lower_atom(atom) do
    atom |> Atom.to_string |> lower_bin |> String.to_atom
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
