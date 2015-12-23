
defmodule Erl2ex.Convert do

  alias Erl2ex.Convert.Context


  def module(erl_module, opts \\ []) do
    context = Context.build(erl_module, opts)
    forms = erl_module.forms |> Enum.map(&(formp(context, &1)))
    forms = [determine_header(context, forms) | forms]
    %Erl2ex.ExModule{
      name: erl_module.name,
      comments: erl_module.comments |> convert_comments,
      forms: forms
    }
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
    and: {[], {:., [], [:erlang, :and]}},
    or: {[], {:., [], [:erlang, :or]}},
    xor: {[], {:., [], [:erlang, :xor]}},
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

    replacement_context = Context.set_quoted_variables(context, args)
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

  defp formp(context, %Erl2ex.ErlRecord{line: line, name: name, fields: fields, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)

    %Erl2ex.ExRecord{
      tag: name,
      macro: Context.record_function_name(context, name),
      fields: list(context, fields),
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp formp(context, %Erl2ex.ErlType{line: line, kind: kind, name: name, params: params, defn: defn, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)

    ex_kind = cond do
      kind == :opaque ->
        :opaque
      Context.is_type_exported?(context, name, Enum.count(params)) ->
        :type
      true ->
        :typep
    end

    %Erl2ex.ExType{
      kind: ex_kind,
      signature: {name, [], list(context, params)},
      defn: expr(context, defn),
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

  defp expr(_context, {:string, _, val}) when is_list(val), do:
    val

  defp expr(context, {:tuple, _, [val1, val2]}), do:
    {expr(context, val1), expr(context, val2)}

  defp expr(context, {:tuple, _, vals}) when is_list(vals), do:
    {:{}, [], vals |> Enum.map(&(expr(context, &1)))}

  defp expr(_context, {nil, _}), do:
    []

  defp expr(context, {:cons, _, head, tail = {:cons, _, _, _}}), do:
    [expr(context, head) | expr(context, tail)]

  defp expr(context, {:cons, _, head, {nil, _}}), do:
    [expr(context, head)]

  defp expr(context, {:cons, _, head, tail}), do:
    [{:|, [], [expr(context, head), expr(context, tail)]}]

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

  defp expr(_context, {:fun, _, {:function, name, arity}}) when is_atom(name) and is_integer(arity), do:
    {:&, [], [{:/, @import_kernel_metadata, [{name, [], Elixir}, arity]}]}

  defp expr(context, {:fun, _, {:function, mod_expr, name_expr, arity_expr}}), do:
    {:&, [], [{:/, @import_kernel_metadata, [{{:., [], [expr(context, mod_expr), expr(context, name_expr)]}, [], []}, expr(context, arity_expr)]}]}

  defp expr(context, {:block, _, arg}) when is_list(arg), do:
    block(context, arg)

  defp expr(context, {:generate, _, into, arg}), do:
    {:<-, [], [expr(context, into), expr(context, arg)]}

  defp expr(context, {:b_generate, _, {:bin, _, elems}, arg}), do:
    bin_generator(context, elems, arg)

  defp expr(context, {:lc, _, expression, qualifiers}), do:
    {:for, [], list(context, qualifiers) ++ [[into: [], do: expr(context, expression)]]}

  defp expr(context, {:bc, _, expression, qualifiers}), do:
    {:for, [], list(context, qualifiers) ++ [[into: "", do: expr(context, expression)]]}

  defp expr(context, {:map_field_assoc, _, lhs, rhs}), do:
    {expr(context, lhs), expr(context, rhs)}

  defp expr(context, {:map_field_exact, _, lhs, rhs}), do:
    {expr(context, lhs), expr(context, rhs)}

  defp expr(context, {:map, _, associations}), do:
    {:%{}, [], list(context, associations)}

  defp expr(context, {:map, _, base_map, []}), do:
    expr(context, base_map)

  defp expr(context, {:map, _, base_map, assocs}), do:
    update_map(context, expr(context, base_map), assocs)

  defp expr(context, {:bin, _, elems}), do:
    {:<<>>, [], list(context, elems)}

  defp expr(context, {:bin_element, _, val, :default, :default}), do:
    bin_element_expr(context, val)

  defp expr(context, {:bin_element, _, val, {:integer, _, size}, :default}), do:
    {:::, [], [bin_element_expr(context, val), size]}

  defp expr(context, {:bin_element, _, val, size, :default}), do:
    {:::, [], [bin_element_expr(context, val), {:size, [], [expr(context, size)]}]}

  defp expr(context, {:bin_element, _, val, :default, [type]}), do:
    {:::, [], [bin_element_expr(context, val), {type, [], Elixir}]}

  defp expr(context, {:record, _, name, fields}), do:
    {Context.record_function_name(context, name), [], [record_field_list(context, name, fields)]}

  defp expr(context, {:record, _, record, name, updates}), do:
    {Context.record_function_name(context, name), [], [expr(context, record), list(context, updates)]}

  defp expr(context, {:record_index, _, name, field}), do:
    Context.record_field_index(context, name, expr(context, field))

  defp expr(context, {:record_field, _, name}), do:
    {expr(context, name), :undefined}

  defp expr(context, {:record_field, _, name, default}), do:
    {expr(context, name), expr(context, default)}

  defp expr(context, {:record_field, _, record, name, field}), do:
    {Context.record_function_name(context, name), [], [expr(context, record), expr(context, field)]}

  defp expr(context, {:type, _, type, params}), do:
    type(context, type, params)


  defp type(_context, :tuple, :any), do:
    {:tuple, [], []}

  defp type(context, :tuple, params), do:
    {:{}, [], list(context, params)}

  defp type(_context, :list, []), do:
    {:list, [], []}

  defp type(context, :list, [type]), do:
    {:list, [], [expr(context, type)]}

  defp type(_context, nil, []), do:
    []

  defp type(context, :range, [from, to]), do:
    {:.., @import_kernel_metadata, [expr(context, from), expr(context, to)]}

  defp type(_context, :binary, [{:integer, _, 0}, {:integer, _, 0}]), do:
    {:<<>>, [], []}

  defp type(context, :binary, [m, {:integer, _, 0}]), do:
    {:<<>>, [], [{:::, [], [{:_, [], Elixir}, expr(context, m)]}]}

  defp type(context, :binary, [{:integer, _, 0}, n]), do:
    {:<<>>, [], [{:::, [], [{:_, [], Elixir}, {:*, @import_kernel_metadata, [{:_, [], Elixir}, expr(context, n)]}]}]}

  defp type(context, :binary, [m, n]), do:
    {:<<>>, [], [{:::, [], [{:_, [], Elixir}, expr(context, m)]}, {:::, [], [{:_, [], Elixir}, {:*, @import_kernel_metadata, [{:_, [], Elixir}, expr(context, n)]}]}]}

  defp type(context, :fun, [{:type, _, :any}, result]), do:
    [{:->, [], [[{:..., [], Elixir}], expr(context, result)]}]

  defp type(context, :fun, [{:type, _, :product, args}, result]), do:
    [{:->, [], [list(context, args), expr(context, result)]}]

  defp type(_context, :map, :any), do:
    {:map, [], []}

  defp type(context, :map, assocs), do:
    {:%{}, [], list(context, assocs)}

  defp type(context, :map_field_assoc, [key, value]), do:
    {expr(context, key), expr(context, value)}

  defp type(context, :union, args), do:
    union(context, args)

  defp type(context, name, params), do:
    {name, [], list(context, params)}


  defp union(context, [h | []]), do:
    expr(context, h)

  defp union(context, [h | t]), do:
    {:|, [], [expr(context, h), union(context, t)]}


  defp record_field_list(context, record_name, fields) do
    {underscores, ex_fields} = list(context, fields)
      |> Enum.partition(fn
        {{:_, _, Elixir}, _} -> true
        {_, _} -> false
      end)
    case underscores do
      [{_, value}] ->
        explicit_field_names = ex_fields |> Enum.map(fn {name, _} -> name end)
        needed_field_names = Context.record_field_names(context, record_name)
        extra_fields = (needed_field_names -- explicit_field_names)
          |> Enum.map(fn name -> {name, value} end)
        ex_fields ++ extra_fields
      _ ->
        ex_fields
    end
  end


  defp bin_generator(context, elems, arg) do
    {elems, [last_elem]} = Enum.split(elems, -1)
    last_ex_elem = {:<-, [], [expr(context, last_elem), expr(context, arg)]}
    {:<<>>, [], list(context, elems) ++ [last_ex_elem]}
  end


  defp bin_element_expr(_context, {:string, _, str}), do: List.to_string(str)
  defp bin_element_expr(context, val), do: expr(context, val)


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


  defp generalized_var(context, _atom_name, << "?" :: utf8, name :: binary >>), do:
    const(context, String.to_atom(name))

  defp generalized_var(context, atom_name, str_name) do
    var = {str_name |> lower_str |> String.to_atom, [], Elixir}
    if Context.is_quoted_var?(context, atom_name) do
      {:unquote, [], [var]}
    else
      var
    end
  end


  defp const(_context, :MODULE), do:
    {:__MODULE__, [], Elixir}

  defp const(_context, :MODULE_STRING), do:
    {{:., [], [{:__aliases__, [alias: false], [:Atom]}, :to_char_list]}, [], [{:__MODULE__, [], Elixir}]}

  defp const(_context, :FILE), do:
    {{:., [], [{:__aliases__, [alias: false], [:String]}, :to_char_list]}, [], [{{:., [], [{:__ENV__, [], Elixir}, :file]}, [], []}]}

  defp const(_context, :LINE), do:
    {{:., [], [{:__ENV__, [], Elixir}, :line]}, [], []}

  defp const(_context, :MACHINE), do:
    'BEAM'

  defp const(context, name) do
    macro_name = Context.macro_const_name(context, name)
    {:@, @import_kernel_metadata, [{macro_name, [], Elixir}]}
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


  defp lower_str("_"), do: "_"
  defp lower_str(<< "_" :: utf8, rest :: binary >>), do:
    << "_" :: utf8, lower_str(rest) :: binary >>
  defp lower_str(<< first :: utf8, rest :: binary >>), do:
    << String.downcase(<< first >>) :: binary, rest :: binary >>

  defp lower_atom(atom), do:
    atom |> Atom.to_string |> lower_str |> String.to_atom


  defp split_comments(comments, line), do:
    comments |> Enum.split_while(fn {:comment, ln, _} -> ln < line end)


  defp convert_comments(comments) do
    comments |> Enum.map(fn {:comment, _, str} ->
      Regex.replace(~r{^%}, to_string(str), "#")
    end)
  end


  defp determine_header(context, forms) do
    header = forms
      |> Enum.reduce(%Erl2ex.ExHeader{}, &header_check_form/2)
    %Erl2ex.ExHeader{header |
      records: Context.map_records(context, fn(name, fields) -> {name, fields} end),
      record_info_available: not Context.is_local_func?(context, :record_info, 2)
    }
  end

  defp header_check_form(%Erl2ex.ExFunc{clauses: clauses}, header), do:
    clauses |> Enum.reduce(header, &header_check_clause/2)
  defp header_check_form(%Erl2ex.ExMacro{expr: expr}, header), do:
    header_check_expr(expr, header)
  defp header_check_form(%Erl2ex.ExAttr{arg: arg}, header), do:
    header_check_expr(arg, header)
  defp header_check_form(_form, header), do: header

  defp header_check_clause(%Erl2ex.ExClause{exprs: exprs}, header), do:
    exprs |> Enum.reduce(header, &header_check_expr/2)

  defp header_check_expr(expr, header)
  when is_tuple(expr) and tuple_size(expr) >= 3 do
    if elem(expr, 1) == @import_bitwise_metadata do
      header = %Erl2ex.ExHeader{header | use_bitwise: true}
    end
    Tuple.to_list(expr) |> Enum.reduce(header, &header_check_expr/2)
  end
  defp header_check_expr(_expr, header), do: header

end
