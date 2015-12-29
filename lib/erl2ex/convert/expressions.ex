
defmodule Erl2ex.Convert.Expressions do

  @moduledoc false

  alias Erl2ex.Convert.Context


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
    apply: :apply,
    bit_size: :bit_size,
    byte_size: :byte_size,
    hd: :hd,
    is_atom: :is_atom,
    is_binary: :is_binary,
    is_bitstring: :is_bitstring,
    is_boolean: :is_boolean,
    is_float: :is_float,
    is_function: :is_function,
    is_integer: :is_integer,
    is_list: :is_list,
    is_map: :is_map,
    is_number: :is_number,
    is_pid: :is_pid,
    is_port: :is_port,
    is_reference: :is_reference,
    is_tuple: :is_tuple,
    length: :length,
    make_ref: :make_ref,
    map_size: :map_size,
    max: :max,
    min: :min,
    node: :node,
    round: :round,
    self: :self,
    throw: :throw,
    tl: :tl,
    trunc: :trunc,
    tuple_size: :tuple_size
  ] |> Enum.into(HashDict.new)


  def conv_expr(_context, {:atom, _, val}) when is_atom(val), do:
    val

  def conv_expr(_context, {:integer, _, val}) when is_integer(val), do:
    val

  def conv_expr(_context, {:char, _, val}) when is_integer(val), do:
    val

  def conv_expr(_context, {:float, _, val}) when is_float(val), do:
    val

  def conv_expr(_context, {:string, _, val}) when is_list(val), do:
    val

  def conv_expr(context, {:tuple, _, [val1, val2]}), do:
    {conv_expr(context, val1), conv_expr(context, val2)}

  def conv_expr(context, {:tuple, _, vals}) when is_list(vals), do:
    {:{}, [], vals |> Enum.map(&(conv_expr(context, &1)))}

  def conv_expr(_context, {nil, _}), do:
    []

  def conv_expr(context, {:cons, _, head, tail = {:cons, _, _, _}}), do:
    [conv_expr(context, head) | conv_expr(context, tail)]

  def conv_expr(context, {:cons, _, head, {nil, _}}), do:
    [conv_expr(context, head)]

  def conv_expr(context, {:cons, _, head, tail}), do:
    [{:|, [], [conv_expr(context, head), conv_expr(context, tail)]}]

  def conv_expr(context, {:var, _, name}) when is_atom(name), do:
    conv_generalized_var(context, Atom.to_string(name))

  def conv_expr(context, {:match, _, lhs, rhs}), do:
    {:=, [], [conv_expr(context, lhs), conv_expr(context, rhs)]}

  def conv_expr(context, {:remote, _, mod, func}), do:
    {:., [], [conv_expr(context, mod), conv_expr(context, func)]}

  def conv_expr(context, {:call, _, func, args}) when is_list(args), do:
    {func_spec(context, func, args), [], conv_list(context, args)}

  def conv_expr(context, {:op, _, op, arg}) do
    {metadata, ex_op} = Dict.fetch!(@op_map, op)
    {ex_op, metadata, [conv_expr(context, arg)]}
  end

  def conv_expr(context, {:op, _, op, arg1, arg2}) do
    {metadata, ex_op} = Dict.fetch!(@op_map, op)
    {ex_op, metadata, [conv_expr(context, arg1), conv_expr(context, arg2)]}
  end

  def conv_expr(context, {:clause, _, [], guards, arg}), do:
    {:"->", [], [[guard_seq(context, guards, nil)], conv_block(context, arg)]}

  def conv_expr(context, {:clause, _, params, [], arg}), do:
    {:"->", [], [conv_list(context, params), conv_block(context, arg)]}

  def conv_expr(context, {:clause, _, params, guards, arg}), do:
    {:"->", [], [[{:when, [], conv_list(context, params) ++ [guard_seq(context, guards, nil)]}], conv_block(context, arg)]}

  def conv_expr(context, {:case, _, val, clauses}) when is_list(clauses), do:
    {:case, [], [conv_expr(context, val), [do: conv_list(context, clauses)]]}

  def conv_expr(context, {:if, _, clauses}) when is_list(clauses), do:
    {:cond, [], [[do: conv_list(context, clauses)]]}

  def conv_expr(context, {:receive, _, clauses}) when is_list(clauses), do:
    {:receive, [], [[do: conv_list(context, clauses)]]}

  def conv_expr(context, {:fun, _, {:clauses, clauses}}) when is_list(clauses), do:
    {:fn, [], conv_list(context, clauses)}

  def conv_expr(_context, {:fun, _, {:function, name, arity}}) when is_atom(name) and is_integer(arity), do:
    {:&, [], [{:/, @import_kernel_metadata, [{name, [], Elixir}, arity]}]}

  def conv_expr(context, {:fun, _, {:function, mod_expr, name_expr, arity_expr}}), do:
    {:&, [], [{:/, @import_kernel_metadata, [{{:., [], [conv_expr(context, mod_expr), conv_expr(context, name_expr)]}, [], []}, conv_expr(context, arity_expr)]}]}

  def conv_expr(context, {:block, _, arg}) when is_list(arg), do:
    conv_block(context, arg)

  def conv_expr(context, {:generate, _, into, arg}), do:
    {:<-, [], [conv_expr(context, into), conv_expr(context, arg)]}

  def conv_expr(context, {:b_generate, _, {:bin, _, elems}, arg}), do:
    bin_generator(context, elems, arg)

  def conv_expr(context, {:lc, _, expr, qualifiers}), do:
    {:for, [], conv_list(context, qualifiers) ++ [[into: [], do: conv_expr(context, expr)]]}

  def conv_expr(context, {:bc, _, expr, qualifiers}), do:
    {:for, [], conv_list(context, qualifiers) ++ [[into: "", do: conv_expr(context, expr)]]}

  def conv_expr(context, {:try, _, expr, of_clauses, catches, after_expr}), do:
    conv_try(context, expr, of_clauses, catches, after_expr)

  def conv_expr(context, {:catch, _, expr}), do:
    conv_catch(context, expr)

  def conv_expr(context, {:map_field_assoc, _, lhs, rhs}), do:
    {conv_expr(context, lhs), conv_expr(context, rhs)}

  def conv_expr(context, {:map_field_exact, _, lhs, rhs}), do:
    {conv_expr(context, lhs), conv_expr(context, rhs)}

  def conv_expr(context, {:map, _, associations}), do:
    {:%{}, [], conv_list(context, associations)}

  def conv_expr(context, {:map, _, base_map, []}), do:
    conv_expr(context, base_map)

  def conv_expr(context, {:map, _, base_map, assocs}), do:
    update_map(context, conv_expr(context, base_map), assocs)

  def conv_expr(context, {:bin, _, elems}), do:
    {:<<>>, [], conv_list(context, elems)}

  def conv_expr(context, {:bin_element, _, val, :default, :default}), do:
    bin_element_expr(context, val)

  def conv_expr(context, {:bin_element, _, val, {:integer, _, size}, :default}), do:
    {:::, [], [bin_element_expr(context, val), size]}

  def conv_expr(context, {:bin_element, _, val, size, :default}), do:
    {:::, [], [bin_element_expr(context, val), {:size, [], [conv_expr(context, size)]}]}

  def conv_expr(context, {:bin_element, _, val, :default, [type]}), do:
    {:::, [], [bin_element_expr(context, val), {type, [], Elixir}]}

  def conv_expr(context, {:record, _, name, fields}), do:
    {Context.record_function_name(context, name), [], [record_field_list(context, name, fields)]}

  def conv_expr(context, {:record, _, record, name, updates}), do:
    {Context.record_function_name(context, name), [], [conv_expr(context, record), conv_list(context, updates)]}

  def conv_expr(context, {:record_index, _, name, field}), do:
    Context.record_field_index(context, name, conv_expr(context, field))

  def conv_expr(context, {:record_field, _, name}), do:
    {conv_expr(context, name), :undefined}

  def conv_expr(context, {:record_field, _, name, default}), do:
    {conv_expr(context, name), conv_expr(context, default)}

  def conv_expr(context, {:record_field, _, record, name, field}), do:
    {Context.record_function_name(context, name), [], [conv_expr(context, record), conv_expr(context, field)]}

  # Elixir doesn't seem to support typed fields in record declarations
  def conv_expr(context, {:typed_record_field, record_field, _type}), do:
    conv_expr(context, record_field)

  def conv_expr(context, {:type, _, type}), do:
    conv_type(context, type)

  def conv_expr(context, {:type, _, type, params}), do:
    conv_type(context, type, params)

  def conv_expr(context, {:type, _, type, param1, param2}), do:
    conv_type(context, type, param1, param2)

  def conv_expr(context, {:ann_type, _, [_var, type]}), do:
    conv_expr(context, type)

  def conv_expr(context, expr), do:
    Utils.handle_error(context, expr)


  def conv_list(context, list) when is_list(list), do:
    list |> Enum.map(&(conv_expr(context, &1)))

  def conv_list(context, expr), do:
    Utils.handle_error(context, expr, "when expecting a list")


  def guard_seq(_context, [], result), do:
    result

  def guard_seq(context, [ghead | gtail], result), do:
    guard_seq(context, gtail, guard_combine(result, guard_elem(context, ghead, nil), :or))


  defp conv_try(context, expr, of_clauses, catches, after_expr) do
    try_elems = [do: conv_block(context, expr)]
    catch_clauses = catches |> Enum.map(&(catch_clause(context, &1)))
    if not Enum.empty?(catch_clauses) do
      try_elems = try_elems ++ [catch: catch_clauses]
    end
    if not Enum.empty?(after_expr) do
      try_elems = try_elems ++ [after: conv_block(context, after_expr)]
    end
    if not Enum.empty?(of_clauses) do
      try_elems = try_elems ++ [else: conv_list(context, of_clauses)]
    end
    {:try, [], [try_elems]}
  end


  defp conv_catch(context, expr) do
    catch_clauses = [
      {:->, [], [[:throw, {:term, [], Elixir}], {:term, [], Elixir}]},
      {:->, [], [[:exit, {:reason, [], Elixir}], {:EXIT, {:reason, [], Elixir}}]},
      {:->, [], [[:error, {:reason, [], Elixir}], {:EXIT, {{:reason, [], Elixir}, {{:., [], [:erlang, :get_stacktrace]}, [], []}}}]}
    ]
    {:try, [], [[do: conv_expr(context, expr), catch: catch_clauses]]}
  end


  defp catch_clause(context, {:clause, _, params, [], arg}) do
    {:"->", [], [catch_params(context, params), conv_block(context, arg)]}
  end

  defp catch_clause(context, {:clause, _, params, guards, arg}) do
    {:"->", [], [[{:when, [], catch_params(context, params) ++ [guard_seq(context, guards, nil)]}], conv_block(context, arg)]}
  end

  defp catch_clause(context, expr), do:
    Utils.handle_error(context, expr, "in a catch clause")


  defp catch_params(context, [{:tuple, _, [{:atom, _, kind}, pattern, {:var, _, :_}]}]), do:
    [kind, conv_expr(context, pattern)]

  defp catch_params(context, expr), do:
    Utils.handle_error(context, expr, "in the set of catch params")


  defp conv_type(_context, :any), do:
    [{:..., [], Elixir}]


  defp conv_type(_context, :tuple, :any), do:
    {:tuple, [], []}

  defp conv_type(context, :tuple, params), do:
    {:{}, [], conv_list(context, params)}

  defp conv_type(_context, :list, []), do:
    {:list, [], []}

  defp conv_type(context, :list, [type]), do:
    {:list, [], [conv_expr(context, type)]}

  defp conv_type(_context, nil, []), do:
    []

  defp conv_type(context, :range, [from, to]), do:
    {:.., @import_kernel_metadata, [conv_expr(context, from), conv_expr(context, to)]}

  defp conv_type(_context, :binary, [{:integer, _, 0}, {:integer, _, 0}]), do:
    {:<<>>, [], []}

  defp conv_type(context, :binary, [m, {:integer, _, 0}]), do:
    {:<<>>, [], [{:::, [], [{:_, [], Elixir}, conv_expr(context, m)]}]}

  defp conv_type(context, :binary, [{:integer, _, 0}, n]), do:
    {:<<>>, [], [{:::, [], [{:_, [], Elixir}, {:*, @import_kernel_metadata, [{:_, [], Elixir}, conv_expr(context, n)]}]}]}

  defp conv_type(context, :binary, [m, n]), do:
    {:<<>>, [], [{:::, [], [{:_, [], Elixir}, conv_expr(context, m)]}, {:::, [], [{:_, [], Elixir}, {:*, @import_kernel_metadata, [{:_, [], Elixir}, conv_expr(context, n)]}]}]}

  defp conv_type(context, :fun, [args, result]), do:
    [{:->, [], [conv_expr(context, args), conv_expr(context, result)]}]

  defp conv_type(context, :product, args), do:
    conv_list(context, args)

  defp conv_type(_context, :map, :any), do:
    {:map, [], []}

  defp conv_type(context, :map, assocs), do:
    {:%{}, [], conv_list(context, assocs)}

  defp conv_type(context, :map_field_assoc, [key, value]), do:
    {conv_expr(context, key), conv_expr(context, value)}

  defp conv_type(context, :record, [name | fields]), do:
    {:record, [], [conv_expr(context, name), conv_list(context, fields)]}

  defp conv_type(context, :field_type, [name, type]), do:
    {conv_expr(context, name), conv_expr(context, type)}

  defp conv_type(context, :union, args), do:
    conv_union(context, args)

  defp conv_type(context, name, params), do:
    {name, [], conv_list(context, params)}


  defp conv_type(context, :map_field_assoc, key, value), do:
    {conv_expr(context, key), conv_expr(context, value)}


  defp conv_union(context, [h | []]), do:
    conv_expr(context, h)

  defp conv_union(context, [h | t]), do:
    {:|, [], [conv_expr(context, h), conv_union(context, t)]}


  defp record_field_list(context, record_name, fields) do
    {underscores, ex_fields} = context
      |> conv_list(fields)
      |> Enum.partition(fn
        {{:_, _, Elixir}, _} -> true
        {_, _} -> false
      end)
    case underscores do
      [{_, value}] ->
        explicit_field_names = ex_fields
          |> Enum.map(fn {name, _} -> name end)
        needed_field_names = Context.record_field_names(context, record_name)
        extra_field_names = (needed_field_names -- explicit_field_names)
        extra_fields = extra_field_names
          |> Enum.map(fn name -> {name, value} end)
        ex_fields ++ extra_fields
      _ ->
        ex_fields
    end
  end


  defp bin_generator(context, elems, arg) do
    {elems, [last_elem]} = Enum.split(elems, -1)
    last_ex_elem = {:<-, [], [conv_expr(context, last_elem), conv_expr(context, arg)]}
    {:<<>>, [], conv_list(context, elems) ++ [last_ex_elem]}
  end


  defp bin_element_expr(_context, {:string, _, str}), do: List.to_string(str)
  defp bin_element_expr(context, val), do: conv_expr(context, val)


  defp update_map(context, base_map, assocs = [{:map_field_exact, _, _, _} | _]) do
    {exact_assocs, remaining_assocs} = assocs
      |> Enum.split_while(fn
        {:map_field_exact, _, _, _} -> true
        _ -> false
      end)
    new_base = {:%{}, [], [{:|, [], [base_map, conv_list(context, exact_assocs)]}]}
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
      [base_map, {:%{}, [], conv_list(context, inexact_assocs)}]
    }
    update_map(context, new_base, remaining_assocs)
  end

  defp update_map(_context, base_map, []), do: base_map


  defp conv_generalized_var(context, name = << "??" :: binary, _ :: binary >>), do:
    conv_normal_var(context, String.to_atom(name))

  defp conv_generalized_var(context, << "?" :: utf8, name :: binary >>), do:
    conv_const(context, String.to_atom(name))

  defp conv_generalized_var(context, name), do:
    conv_normal_var(context, String.to_atom(name))


  defp conv_normal_var(context, name) do
    mapped_name = Context.map_variable_name(context, name)
    var = {mapped_name, [], Elixir}
    if Context.is_quoted_var?(context, mapped_name) do
      {:unquote, [], [var]}
    else
      var
    end
  end


  defp conv_const(_context, :MODULE), do:
    {:__MODULE__, [], Elixir}

  defp conv_const(_context, :MODULE_STRING), do:
    {{:., [], [{:__aliases__, [alias: false], [:Atom]}, :to_char_list]}, [], [{:__MODULE__, [], Elixir}]}

  defp conv_const(_context, :FILE), do:
    {{:., [], [{:__aliases__, [alias: false], [:String]}, :to_char_list]}, [], [{{:., [], [{:__ENV__, [], Elixir}, :file]}, [], []}]}

  defp conv_const(_context, :LINE), do:
    {{:., [], [{:__ENV__, [], Elixir}, :line]}, [], []}

  defp conv_const(_context, :MACHINE), do:
    'BEAM'

  defp conv_const(context, name) do
    macro_name = Context.macro_const_name(context, name)
    {:@, @import_kernel_metadata, [{macro_name, [], Elixir}]}
  end


  defp func_spec(context, func = {:remote, _, _, _}, _args), do:
    conv_expr(context, func)

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
        {:., [], [conv_expr(context, func)]}
    end
  end

  defp func_spec(context, func, _args), do:
    {:., [], [conv_expr(context, func)]}


  defp conv_block(context, [arg]), do:
    conv_expr(context, arg)

  defp conv_block(context, arg) when is_list(arg), do:
    {:__block__, [], conv_list(context, arg)}


  defp guard_elem(_context, [], result), do:
    result

  defp guard_elem(context, [ghead | gtail], result), do:
    # TODO: Make sure we can get away with conv_expr. Erlang guards can conceivably
    # resolve to a value other than true or false, which for Erlang should
    # fail the guard, but in Elixir will succeed the guard. If this is a
    # problem, the Elixir version might need to compare === true.
    guard_elem(context, gtail, guard_combine(result, conv_expr(context, ghead), :and))


  defp guard_combine(nil, rhs, _op), do:
    rhs

  defp guard_combine(lhs, rhs, op), do:
    {op, @import_kernel_metadata, [lhs, rhs]}


end
