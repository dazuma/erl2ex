
defmodule Erl2ex.Convert do

  @import_context [context: Elixir, import: Kernel]

  @op_map [
    ==: :==,
    "/=": :!=,
    "=<": :<=,
    >=: :>=,
    <: :<,
    >: :>,
    "=:=": :===,
    "=/=": :!==,
    +: :+,
    -: :-,
    *: :*,
    /: :/
  ] |> Enum.into(HashDict.new)


  def module(erl_module, opts \\ []) do
    %Erl2ex.ExModule{
      name: erl_module.name,
      comments: erl_module.comments |> convert_comments,
      forms: erl_module.forms |> Enum.map(&(form(&1, erl_module)))
    }
  end


  def form(%Erl2ex.ErlFunc{name: name, arity: arity, clauses: clauses, comments: comments}, erl_module) do
    [%{line: first_line} | _] = clauses
    {main_comments, clause_comments} = split_comments(comments, first_line)
    {clauses, _} = clauses
      |> Enum.map_reduce(clause_comments, &clause/2)

    %Erl2ex.ExFunc{
      name: name,
      arity: arity,
      public: Enum.member?(erl_module.exports, {name, arity}),
      comments: main_comments |> convert_comments,
      clauses: clauses
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


  def expr(list) when is_list(list) do
    list |> Enum.map(&expr/1)
  end
  def expr({:atom, _, val}) when is_atom(val) do
    val
  end
  def expr({:integer, _, val}) when is_integer(val) do
    val
  end
  def expr({:float, _, val}) when is_float(val) do
    val
  end
  def expr({:tuple, _, [val1, val2]}) do
    {val1, val2}
  end
  def expr({:tuple, _, vals}) when is_list(vals) do
    {:{}, [], vals |> Enum.map(&expr/1)}
  end
  def expr({nil, _}) do
    []
  end
  def expr({:cons, _, head, tail}) do
    [head | expr(tail)]
  end
  def expr({:var, _, name}) when is_atom(name) do
    {lower_atom(name), [], Elixir}
  end
  def expr({:match, _, lhs, rhs}) do
    {:=, [], [expr(lhs), expr(rhs)]}
  end
  def expr({:remote, _, mod, func}) do
    {:., [], [expr(mod), expr(func)]}
  end
  def expr({:call, _, func, args}) when is_list(args) do
    {expr(func), [], expr(args)}
  end
  def expr({:op, _, op, arg1, arg2}) do
    {Dict.fetch!(@op_map, op), @import_context, [expr(arg1), expr(arg2)]}
  end


  defp guard_seq([], result) do
    result
  end
  defp guard_seq([ghead | gtail], result) do
    guard_seq(gtail, guard_combine(result, guard_elem(ghead, nil), :or))
  end

  defp guard_elem([], result) do
    result
  end
  defp guard_elem([ghead | gtail], result) do
    # TODO: Make sure we can get away with expr. Erlang guards can conceivably
    # resolve to a value other than true or false, which for Erlang should
    # fail the guard, but in Elixir will succeed the guard. If this is a
    # problem, the Elixir version might need to compare === true.
    guard_seq(gtail, guard_combine(result, expr(ghead), :and))
  end

  defp guard_combine(nil, rhs, _op) do
    rhs
  end
  defp guard_combine(lhs, rhs, op) do
    {op, @import_context, [lhs, rhs]}
  end


  defp clause(erl_clause, comments) do
    line = erl_clause.line
    lines = line_range(erl_clause.exprs, line..line)
    {head_comments, comments} = split_comments(comments, lines.first)
    {inline_comments, remaining_comments} = split_comments(comments, lines.last)
    ex_clause = %Erl2ex.ExClause{
      args: expr(erl_clause.args),
      guard: guard_seq(erl_clause.guards, nil),
      exprs: expr(erl_clause.exprs),
      comments: head_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
    {ex_clause, remaining_comments}
  end


  defp line_range([], range) do
    range
  end
  defp line_range([val | rest], range) do
    line_range(rest, line_range(val, range))
  end
  defp line_range({_, line, val1}, range) do
    line_range(val1, range |> add_range(line))
  end
  defp line_range({_, line, _val1, val2}, range) do
    line_range(val2, add_range(range, line))
  end
  defp line_range({_, line, _val1, _val2, val3}, range) do
    line_range(val3, add_range(range, line))
  end
  defp line_range({_, line}, range) do
    add_range(range, line)
  end
  defp line_range(_, range) do
    range
  end


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
