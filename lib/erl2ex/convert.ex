
defmodule Erl2ex.Convert do

  @moduledoc false

  alias Erl2ex.Convert.Context


  def module(erl_module, opts \\ []) do
    context = Context.build(erl_module, opts)
    forms = erl_module.forms |> Enum.map(&(conv_form(context, &1)))
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

  @auto_registered_attrs [:vsn, :compile, :on_load, :behaviour, :behavior]


  defp conv_form(context, %Erl2ex.ErlFunc{name: name, arity: arity, clauses: clauses, comments: comments}) do
    mapped_name = Context.local_function_name(context, name)
    is_exported = Context.is_exported?(context, name, arity)
    first_line = clauses |> List.first |> elem(1)
    {main_comments, clause_comments} = split_comments(comments, first_line)
    {ex_clauses, _} = clauses
      |> Enum.map_reduce(clause_comments, &(clause(context, &1, &2, mapped_name)))
    spec_info = Context.specs_for_func(context, name)
    main_comments = spec_info.comments ++ main_comments
    specs = spec_info.clauses |> Enum.map(&(conv_spec_clause(context, mapped_name, &1)))

    %Erl2ex.ExFunc{
      name: mapped_name,
      arity: arity,
      public: is_exported,
      specs: specs,
      comments: main_comments |> convert_comments,
      clauses: ex_clauses
    }
  end

  defp conv_form(_context, %Erl2ex.ErlImport{line: line, module: mod, funcs: funcs, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)

    %Erl2ex.ExImport{
      module: mod,
      funcs: funcs,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(_context, %Erl2ex.ErlAttr{name: name, line: line, arg: arg, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    {name, arg} = conv_attr(name, arg)
    register = not name in @auto_registered_attrs

    %Erl2ex.ExAttr{
      name: name,
      register: register,
      arg: arg,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(context, %Erl2ex.ErlDefine{line: line, name: name, args: nil, replacement: replacement, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    mapped_name = Context.macro_const_name(context, name)
    tracking_name = Context.tracking_attr_name(context, name)

    %Erl2ex.ExAttr{
      name: mapped_name,
      tracking_name: tracking_name,
      arg: conv_expr(context, replacement),
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(context, %Erl2ex.ErlDefine{line: line, name: name, args: args, replacement: replacement, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)

    replacement_context = Context.set_quoted_variables(context, args)
    ex_args = args |> Enum.map(fn arg -> {lower_atom(arg), [], Elixir} end)
    mapped_name = Context.macro_function_name(context, name)
    tracking_name = Context.tracking_attr_name(context, name)

    %Erl2ex.ExMacro{
      signature: {mapped_name, [], ex_args},
      tracking_name: tracking_name,
      expr: conv_expr(replacement_context, replacement),
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(context, %Erl2ex.ErlDirective{line: line, directive: directive, name: name, comments: comments}) do
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

  defp conv_form(context, %Erl2ex.ErlRecord{line: line, name: name, fields: fields, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)

    %Erl2ex.ExRecord{
      tag: name,
      macro: Context.record_function_name(context, name),
      fields: conv_list(context, fields),
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(context, %Erl2ex.ErlType{line: line, kind: kind, name: name, params: params, defn: defn, comments: comments}) do
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
      signature: {name, [], conv_list(context, params)},
      defn: conv_expr(context, defn),
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end

  defp conv_form(context, %Erl2ex.ErlSpec{line: line, name: name, clauses: clauses, comments: comments}) do
    {main_comments, inline_comments} = split_comments(comments, line)
    specs = clauses |> Enum.map(&(conv_spec_clause(context, name, &1)))

    %Erl2ex.ExCallback{
      name: name,
      specs: specs,
      comments: main_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
  end


  defp conv_attr(:on_load, {name, 0}), do: {:on_load, name}
  defp conv_attr(:behavior, behaviour), do: {:behaviour, behaviour}
  defp conv_attr(attr, val), do: {attr, val}


  # Expression rules

  defp conv_expr(_context, {:atom, _, val}) when is_atom(val), do:
    val

  defp conv_expr(_context, {:integer, _, val}) when is_integer(val), do:
    val

  defp conv_expr(_context, {:char, _, val}) when is_integer(val), do:
    val

  defp conv_expr(_context, {:float, _, val}) when is_float(val), do:
    val

  defp conv_expr(_context, {:string, _, val}) when is_list(val), do:
    val

  defp conv_expr(context, {:tuple, _, [val1, val2]}), do:
    {conv_expr(context, val1), conv_expr(context, val2)}

  defp conv_expr(context, {:tuple, _, vals}) when is_list(vals), do:
    {:{}, [], vals |> Enum.map(&(conv_expr(context, &1)))}

  defp conv_expr(_context, {nil, _}), do:
    []

  defp conv_expr(context, {:cons, _, head, tail = {:cons, _, _, _}}), do:
    [conv_expr(context, head) | conv_expr(context, tail)]

  defp conv_expr(context, {:cons, _, head, {nil, _}}), do:
    [conv_expr(context, head)]

  defp conv_expr(context, {:cons, _, head, tail}), do:
    [{:|, [], [conv_expr(context, head), conv_expr(context, tail)]}]

  defp conv_expr(context, {:var, _, name}) when is_atom(name), do:
    generalized_var(context, name, Atom.to_string(name))

  defp conv_expr(context, {:match, _, lhs, rhs}), do:
    {:=, [], [conv_expr(context, lhs), conv_expr(context, rhs)]}

  defp conv_expr(context, {:remote, _, mod, func}), do:
    {:., [], [conv_expr(context, mod), conv_expr(context, func)]}

  defp conv_expr(context, {:call, _, func, args}) when is_list(args), do:
    {func_spec(context, func, args), [], conv_list(context, args)}

  defp conv_expr(context, {:op, _, op, arg}) do
    {metadata, ex_op} = Dict.fetch!(@op_map, op)
    {ex_op, metadata, [conv_expr(context, arg)]}
  end

  defp conv_expr(context, {:op, _, op, arg1, arg2}) do
    {metadata, ex_op} = Dict.fetch!(@op_map, op)
    {ex_op, metadata, [conv_expr(context, arg1), conv_expr(context, arg2)]}
  end

  defp conv_expr(context, {:clause, _, [], guards, arg}), do:
    {:"->", [], [[guard_seq(context, guards, nil)], conv_block(context, arg)]}

  defp conv_expr(context, {:clause, _, params, [], arg}), do:
    {:"->", [], [conv_list(context, params), conv_block(context, arg)]}

  defp conv_expr(context, {:clause, _, params, guards, arg}), do:
    {:"->", [], [[{:when, [], conv_list(context, params) ++ [guard_seq(context, guards, nil)]}], conv_block(context, arg)]}

  defp conv_expr(context, {:case, _, val, clauses}) when is_list(clauses), do:
    {:case, [], [conv_expr(context, val), [do: conv_list(context, clauses)]]}

  defp conv_expr(context, {:if, _, clauses}) when is_list(clauses), do:
    {:cond, [], [[do: conv_list(context, clauses)]]}

  defp conv_expr(context, {:receive, _, clauses}) when is_list(clauses), do:
    {:receive, [], [[do: conv_list(context, clauses)]]}

  defp conv_expr(context, {:fun, _, {:clauses, clauses}}) when is_list(clauses), do:
    {:fn, [], conv_list(context, clauses)}

  defp conv_expr(_context, {:fun, _, {:function, name, arity}}) when is_atom(name) and is_integer(arity), do:
    {:&, [], [{:/, @import_kernel_metadata, [{name, [], Elixir}, arity]}]}

  defp conv_expr(context, {:fun, _, {:function, mod_expr, name_expr, arity_expr}}), do:
    {:&, [], [{:/, @import_kernel_metadata, [{{:., [], [conv_expr(context, mod_expr), conv_expr(context, name_expr)]}, [], []}, conv_expr(context, arity_expr)]}]}

  defp conv_expr(context, {:block, _, arg}) when is_list(arg), do:
    conv_block(context, arg)

  defp conv_expr(context, {:generate, _, into, arg}), do:
    {:<-, [], [conv_expr(context, into), conv_expr(context, arg)]}

  defp conv_expr(context, {:b_generate, _, {:bin, _, elems}, arg}), do:
    bin_generator(context, elems, arg)

  defp conv_expr(context, {:lc, _, expression, qualifiers}), do:
    {:for, [], conv_list(context, qualifiers) ++ [[into: [], do: conv_expr(context, expression)]]}

  defp conv_expr(context, {:bc, _, expression, qualifiers}), do:
    {:for, [], conv_list(context, qualifiers) ++ [[into: "", do: conv_expr(context, expression)]]}

  defp conv_expr(context, {:map_field_assoc, _, lhs, rhs}), do:
    {conv_expr(context, lhs), conv_expr(context, rhs)}

  defp conv_expr(context, {:map_field_exact, _, lhs, rhs}), do:
    {conv_expr(context, lhs), conv_expr(context, rhs)}

  defp conv_expr(context, {:map, _, associations}), do:
    {:%{}, [], conv_list(context, associations)}

  defp conv_expr(context, {:map, _, base_map, []}), do:
    conv_expr(context, base_map)

  defp conv_expr(context, {:map, _, base_map, assocs}), do:
    update_map(context, conv_expr(context, base_map), assocs)

  defp conv_expr(context, {:bin, _, elems}), do:
    {:<<>>, [], conv_list(context, elems)}

  defp conv_expr(context, {:bin_element, _, val, :default, :default}), do:
    bin_element_expr(context, val)

  defp conv_expr(context, {:bin_element, _, val, {:integer, _, size}, :default}), do:
    {:::, [], [bin_element_expr(context, val), size]}

  defp conv_expr(context, {:bin_element, _, val, size, :default}), do:
    {:::, [], [bin_element_expr(context, val), {:size, [], [conv_expr(context, size)]}]}

  defp conv_expr(context, {:bin_element, _, val, :default, [type]}), do:
    {:::, [], [bin_element_expr(context, val), {type, [], Elixir}]}

  defp conv_expr(context, {:record, _, name, fields}), do:
    {Context.record_function_name(context, name), [], [record_field_list(context, name, fields)]}

  defp conv_expr(context, {:record, _, record, name, updates}), do:
    {Context.record_function_name(context, name), [], [conv_expr(context, record), conv_list(context, updates)]}

  defp conv_expr(context, {:record_index, _, name, field}), do:
    Context.record_field_index(context, name, conv_expr(context, field))

  defp conv_expr(context, {:record_field, _, name}), do:
    {conv_expr(context, name), :undefined}

  defp conv_expr(context, {:record_field, _, name, default}), do:
    {conv_expr(context, name), conv_expr(context, default)}

  defp conv_expr(context, {:record_field, _, record, name, field}), do:
    {Context.record_function_name(context, name), [], [conv_expr(context, record), conv_expr(context, field)]}

  # Elixir doesn't seem to support typed fields in record declarations
  defp conv_expr(context, {:typed_record_field, record_field, _type}), do:
    conv_expr(context, record_field)

  defp conv_expr(context, {:type, _, type}), do:
    conv_type(context, type)

  defp conv_expr(context, {:type, _, type, params}), do:
    conv_type(context, type, params)

  defp conv_expr(context, {:type, _, type, param1, param2}), do:
    conv_type(context, type, param1, param2)

  defp conv_expr(context, {:ann_type, _, [_var, type]}), do:
    conv_expr(context, type)


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


  defp generalized_var(context, _atom_name, << "?" :: utf8, name :: binary >>), do:
    conv_const(context, String.to_atom(name))

  defp generalized_var(context, atom_name, str_name) do
    var = {str_name |> lower_str |> String.to_atom, [], Elixir}
    if Context.is_quoted_var?(context, atom_name) do
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


  defp conv_list(context, list) when is_list(list), do:
    list |> Enum.map(&(conv_expr(context, &1)))


  defp conv_spec_clause(context, name, {:type, _, :fun, [args, result]}), do:
    {:::, [], [{name, [], conv_expr(context, args)}, conv_expr(context, result)]}

  defp conv_spec_clause(context, name, {:type, _, :bounded_fun, [func, constraints]}), do:
    {:when, [], [conv_spec_clause(context, name, func), Enum.map(constraints, &(conv_spec_constraint(context, &1)))]}

  defp conv_spec_constraint(context, {:type, _, :constraint, [{:atom, _, :is_subtype}, [{:var, _, var}, type]]}), do:
    {lower_atom(var), conv_expr(context, type)}


  defp clause(context, {:clause, line, args, guards, exprs}, comments, name) do
    lines = line_range(exprs, line..line)
    {head_comments, comments} = split_comments(comments, lines.first)
    {inline_comments, remaining_comments} = split_comments(comments, lines.last)
    ex_clause = %Erl2ex.ExClause{
      signature: clause_signature(context, name, args, guards),
      exprs: conv_list(context, exprs),
      comments: head_comments |> convert_comments,
      inline_comments: inline_comments |> convert_comments
    }
    {ex_clause, remaining_comments}
  end


  defp clause_signature(context, name, params, []), do:
    {name, [], conv_list(context, params)}

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
    # TODO: Make sure we can get away with conv_expr. Erlang guards can conceivably
    # resolve to a value other than true or false, which for Erlang should
    # fail the guard, but in Elixir will succeed the guard. If this is a
    # problem, the Elixir version might need to compare === true.
    guard_elem(context, gtail, guard_combine(result, conv_expr(context, ghead), :and))


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

  defp header_check_expr(expr, header) when is_tuple(expr) and tuple_size(expr) >= 3 do
    if elem(expr, 1) == @import_bitwise_metadata do
      header = %Erl2ex.ExHeader{header | use_bitwise: true}
    end
    expr
      |> Tuple.to_list
      |> Enum.reduce(header, &header_check_expr/2)
  end
  defp header_check_expr(_expr, header), do: header

end
