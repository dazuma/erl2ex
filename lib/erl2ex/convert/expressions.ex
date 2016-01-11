
defmodule Erl2ex.Convert.Expressions do

  @moduledoc false

  alias Erl2ex.Convert.Context
  alias Erl2ex.Convert.Utils


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
  ] |> Enum.into(%{})

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
  ] |> Enum.into(%{})


  def conv_expr({:atom, _, val}, context) when is_atom(val) do
    {val, context}
  end

  def conv_expr({:integer, _, val}, context) when is_integer(val) do
    {val, context}
  end

  def conv_expr({:char, _, val}, context) when is_integer(val) do
    {val, context}
  end

  def conv_expr({:float, _, val}, context) when is_float(val) do
    {val, context}
  end

  def conv_expr({:string, _, val}, context) when is_list(val) do
    {val, context}
  end

  def conv_expr({nil, _}, context) do
    {[], context}
  end

  def conv_expr({:tuple, _, [val1, val2]}, context) do
    {ex_val1, context} = conv_expr(val1, context)
    {ex_val2, context} = conv_expr(val2, context)
    {{ex_val1, ex_val2}, context}
  end

  def conv_expr({:tuple, _, vals}, context) when is_list(vals) do
    {ex_vals, context} = Enum.map_reduce(vals, context, &conv_expr/2)
    {{:{}, [], ex_vals}, context}
  end

  def conv_expr({:cons, _, head, tail = {:cons, _, _, _}}, context) do
    {ex_head, context} = conv_expr(head, context)
    {ex_tail, context} = conv_expr(tail, context)
    {[ex_head | ex_tail], context}
  end

  def conv_expr({:cons, _, head, {nil, _}}, context) do
    {ex_head, context} = conv_expr(head, context)
    {[ex_head], context}
  end

  def conv_expr({:cons, _, head, tail}, context) do
    {ex_head, context} = conv_expr(head, context)
    {ex_tail, context} = conv_expr(tail, context)
    {[{:|, [], [ex_head, ex_tail]}], context}
  end

  def conv_expr({:var, _, name}, context) when is_atom(name) do
    conv_generalized_var(Atom.to_string(name), context)
  end

  def conv_expr({:match, _, lhs, rhs}, context) do
    context = Context.push_match_level(context, false)
    {ex_lhs, context} = conv_expr(lhs, context)
    context = Context.pop_match_level(context)
    {ex_rhs, context} = conv_expr(rhs, context)
    {{:=, [], [ex_lhs, ex_rhs]}, context}
  end

  def conv_expr({:remote, _, mod, func}, context) do
    {ex_mod, context} = conv_expr(mod, context)
    {ex_func, context} = conv_expr(func, context)
    {{:., [], [ex_mod, ex_func]}, context}
  end

  def conv_expr({:call, _, func, args}, context) when is_list(args) do
    conv_call(func, args, context)
  end

  def conv_expr({:op, _, op, arg}, context) do
    {metadata, ex_op} = Map.fetch!(@op_map, op)
    {ex_arg, context} = conv_expr(arg, context)
    {{ex_op, metadata, [ex_arg]}, context}
  end

  def conv_expr({:op, _, op, arg1, arg2}, context) do
    {metadata, ex_op} = Map.fetch!(@op_map, op)
    {ex_arg1, context} = conv_expr(arg1, context)
    {ex_arg2, context} = conv_expr(arg2, context)
    {{ex_op, metadata, [ex_arg1, ex_arg2]}, context}
  end

  def conv_expr({:case, _, val, clauses}, context) when is_list(clauses) do
    {ex_val, context} = conv_expr(val, context)
    {ex_clauses, context} = conv_clause_list(:case, clauses, context)
    {{:case, [], [ex_val, [do: ex_clauses]]}, context}
  end

  def conv_expr({:if, _, clauses}, context) when is_list(clauses) do
    {ex_clauses, context} = conv_clause_list(:if, clauses, context)
    {{:cond, [], [[do: ex_clauses]]}, context}
  end

  def conv_expr({:receive, _, clauses}, context) when is_list(clauses) do
    {ex_clauses, context} = conv_clause_list(:receive, clauses, context)
    {{:receive, [], [[do: ex_clauses]]}, context}
  end

  def conv_expr({:receive, _, clauses, timeout, ontimeout}, context) when is_list(clauses) and is_list(ontimeout) do
    {ex_clauses, context} = conv_clause_list(:receive, clauses, context)
    {ex_timeout, context} = conv_expr(timeout, context)
    {ex_ontimeout, context} = conv_block(ontimeout, context)
    {{:receive, [], [[do: ex_clauses, after: [{:"->", [], [[ex_timeout], ex_ontimeout]}]]]}, context}
  end

  def conv_expr({:fun, _, {:clauses, clauses}}, context) when is_list(clauses) do
    {ex_clauses, context} = conv_clause_list(:fun, clauses, context)
    {{:fn, [], ex_clauses}, context}
  end

  def conv_expr({:fun, _, {:function, name, arity}}, context) when is_atom(name) and is_integer(arity) do
    {{:&, [], [{:/, @import_kernel_metadata, [{name, [], Elixir}, arity]}]}, context}
  end

  def conv_expr({:fun, _, {:function, mod_expr, name_expr, arity_expr}}, context) do
    {ex_mod, context} = conv_expr(mod_expr, context)
    {ex_name, context} = conv_expr(name_expr, context)
    {ex_arity, context} = conv_expr(arity_expr, context)
    {{:&, [], [{:/, @import_kernel_metadata, [{{:., [], [ex_mod, ex_name]}, [], []}, ex_arity]}]}, context}
  end

  def conv_expr({:block, _, arg}, context) when is_list(arg) do
    conv_block(arg, context)
  end

  def conv_expr({:generate, _, into, arg}, context) do
    {ex_into, context} = conv_expr(into, context)
    {ex_arg, context} = conv_expr(arg, context)
    {{:<-, [], [ex_into, ex_arg]}, context}
  end

  def conv_expr({:b_generate, _, {:bin, _, elems}, arg}, context) do
    bin_generator(elems, arg, context)
  end

  def conv_expr({:lc, _, expr, qualifiers}, context) do
    {ex_expr, context} = conv_expr(expr, context)
    {ex_qualifiers, context} = conv_list(qualifiers, context)
    {{:for, [], ex_qualifiers ++ [[into: [], do: ex_expr]]}, context}
  end

  def conv_expr({:bc, _, expr, qualifiers}, context) do
    {ex_expr, context} = conv_expr(expr, context)
    {ex_qualifiers, context} = conv_list(qualifiers, context)
    {{:for, [], ex_qualifiers ++ [[into: "", do: ex_expr]]}, context}
  end

  def conv_expr({:try, _, expr, of_clauses, catches, after_expr}, context) do
    conv_try(expr, of_clauses, catches, after_expr, context)
  end

  def conv_expr({:catch, _, expr}, context) do
    conv_catch(expr, context)
  end

  def conv_expr({node_type, _, lhs, rhs}, context)
  when node_type == :map_field_assoc or node_type == :map_field_exact do
    {ex_lhs, context} = conv_expr(lhs, context)
    {ex_rhs, context} = conv_expr(rhs, context)
    {{ex_lhs, ex_rhs}, context}
  end

  def conv_expr({:map, _, associations}, context) do
    {ex_associations, context} = conv_list(associations, context)
    {{:%{}, [], ex_associations}, context}
  end

  def conv_expr({:map, _, base_map, []}, context) do
    conv_expr(base_map, context)
  end

  def conv_expr({:map, _, base_map, assocs}, context) do
    {ex_base_map, context} = conv_expr(base_map, context)
    update_map(ex_base_map, assocs, context)
  end

  def conv_expr({:bin, _, elems}, context) do
    {ex_elems, context} = conv_list(elems, context)
    {{:<<>>, [], ex_elems}, context}
  end

  def conv_expr({:bin_element, _, val, :default, :default}, context) do
    bin_element_expr(val, context)
  end

  def conv_expr({:bin_element, _, val, :default, [type]}, context) do
    {ex_val, context} = bin_element_expr(val, context)
    {{:::, [], [ex_val, {type, [], Elixir}]}, context}
  end

  def conv_expr({:bin_element, _, val, size, typespec}, context)
  when typespec == :default or typespec == [:binary] do
    {ex_val, context} = bin_element_expr(val, context)
    {ex_size, context} = bin_element_size(size, context)
    {{:::, [], [ex_val, ex_size]}, context}
  end

  def conv_expr({:record, _, name, fields}, context) do
    {ex_fields, context} = record_field_list(name, fields, context)
    {{Context.record_function_name(context, name), [], [ex_fields]}, context}
  end

  def conv_expr({:record, _, record, name, updates}, context) do
    {ex_record, context} = conv_expr(record, context)
    {ex_updates, context} = conv_list(updates, context)
    {{Context.record_function_name(context, name), [], [ex_record, ex_updates]}, context}
  end

  def conv_expr({:record_index, _, name, field}, context) do
    # TODO: consider using a semantic name for this.
    {ex_field, context} = conv_expr(field, context)
    {Context.record_field_index(context, name, ex_field), context}
  end

  def conv_expr({:record_field, _, name}, context) do
    {ex_name, context} = conv_expr(name, context)
    {{ex_name, :undefined}, context}
  end

  def conv_expr({:record_field, _, name, default}, context) do
    {ex_name, context} = conv_expr(name, context)
    {ex_default, context} = conv_expr(default, context)
    {{ex_name, ex_default}, context}
  end

  def conv_expr({:record_field, _, record, name, field}, context) do
    {ex_record, context} = conv_expr(record, context)
    {ex_field, context} = conv_expr(field, context)
    {{Context.record_function_name(context, name), [], [ex_record, ex_field]}, context}
  end

  # Elixir doesn't seem to support typed fields in record declarations
  def conv_expr({:typed_record_field, record_field, _type}, context) do
    conv_expr(record_field, context)
  end

  def conv_expr({:type, _, type}, context) do
    conv_type(type, context)
  end

  def conv_expr({:type, _, type, params}, context) do
    conv_type(type, params, context)
  end

  def conv_expr({:type, _, type, param1, param2}, context) do
    conv_type(type, param1, param2, context)
  end

  def conv_expr({:user_type, _, type, params}, context) do
    conv_type(type, params, context)
  end

  def conv_expr({:remote_type, _, [remote, type, params]}, context) do
    {ex_remote, context} = conv_expr(remote, context)
    {ex_type, context} = conv_expr(type, context)
    conv_type({:., [], [ex_remote, ex_type]}, params, context)
  end

  def conv_expr({:ann_type, _, [_var, type]}, context) do
    conv_expr(type, context)
  end

  def conv_expr(expr, context) do
    Utils.handle_error(context, expr)
  end


  def conv_list(list, context) when is_list(list) do
    Enum.map_reduce(list, context, &conv_expr/2)
  end

  def conv_list(expr, context) do
    Utils.handle_error(context, expr, "when expecting a list")
  end


  defp conv_clause_list(type, clauses, context) do
    if type == :case or type == :if or type == :receive do
      context = Context.clear_exports(context)
    end
    {result, context} = Enum.map_reduce(clauses, context, fn
      ({:clause, _, params, guards, arg}, context) ->
        context = Context.push_scope(context)
        {result, context} = conv_clause(type, params, guards, arg, context)
        context = Context.pop_scope(context)
        {result, context}
    end)
    if type == :case or type == :if or type == :receive do
      context = Context.apply_exports(context)
    end
    {result, context}
  end


  defp conv_clause(:catch, [], _guards, _expr, context) do
    Utils.handle_error(context, [], "in a catch clause (no params)")
  end

  defp conv_clause(_type, [], guards, expr, context) do
    {ex_guards, context} = guard_seq(guards, context)
    {ex_expr, context} = conv_block(expr, context)
    {{:"->", [], [ex_guards, ex_expr]}, context}
  end

  defp conv_clause(type, params, [], expr, context) do
    {ex_params, context} = conv_clause_params(type, params, context)
    {ex_expr, context} = conv_block(expr, context)
    {{:"->", [], [ex_params, ex_expr]}, context}
  end

  defp conv_clause(type, params, guards, expr, context) do
    {ex_params, context} = conv_clause_params(type, params, context)
    {ex_guards, context} = guard_seq(guards, context)
    {ex_expr, context} = conv_block(expr, context)
    {{:"->", [], [[{:when, [], ex_params ++ ex_guards}], ex_expr]}, context}
  end


  defp conv_clause_params(:catch, [{:tuple, _, [kind, pattern, {:var, _, :_}]}], context) do
    context = Context.push_match_level(context, false)
    {ex_kind, context} = conv_expr(kind, context)
    {ex_pattern, context} = conv_expr(pattern, context)
    context = Context.pop_match_level(context)
    {[ex_kind, ex_pattern], context}
  end

  defp conv_clause_params(:catch, expr, context) do
    Utils.handle_error(context, expr, "in the set of catch params")
  end

  defp conv_clause_params(type, expr, context) do
    context = Context.push_match_level(context, type == :fun)
    {ex_expr, context} = conv_list(expr, context)
    context = Context.pop_match_level(context)
    {ex_expr, context}
  end


  def guard_seq([], context) do
    {[], context}
  end
  def guard_seq(guards, context) do
    {result, context} = guard_seq(guards, nil, context)
    {[result], context}
  end

  defp guard_seq([], result, context) do
    {result, context}
  end
  defp guard_seq([ghead | gtail], result, context) do
    {ex_ghead, context} = guard_elem(ghead, nil, context)
    guard_seq(gtail, guard_combine(result, ex_ghead, :or), context)
  end


  defp conv_block([arg], context) do
    conv_expr(arg, context)
  end

  defp conv_block(arg, context) when is_list(arg) do
    {ex_arg, context} = conv_list(arg, context)
    {{:__block__, [], ex_arg}, context}
  end


  defp conv_try(expr, of_clauses, catches, after_expr, context) do
    {ex_expr, context} = conv_block(expr, context)
    try_elems = [do: ex_expr]
    {catch_clauses, context} = conv_clause_list(:catch, catches, context)
    if not Enum.empty?(catch_clauses) do
      try_elems = try_elems ++ [catch: catch_clauses]
    end
    if not Enum.empty?(after_expr) do
      {ex_after_expr, context} = conv_block(after_expr, context)
      try_elems = try_elems ++ [after: ex_after_expr]
    end
    if not Enum.empty?(of_clauses) do
      {ex_of_clauses, context} = conv_clause_list(:try_of, of_clauses, context)
      try_elems = try_elems ++ [else: ex_of_clauses]
    end
    {{:try, [], [try_elems]}, context}
  end


  defp conv_catch(expr, context) do
    catch_clauses = [
      {:->, [], [[:throw, {:term, [], Elixir}], {:term, [], Elixir}]},
      {:->, [], [[:exit, {:reason, [], Elixir}], {:EXIT, {:reason, [], Elixir}}]},
      {:->, [], [[:error, {:reason, [], Elixir}], {:EXIT, {{:reason, [], Elixir}, {{:., [], [:erlang, :get_stacktrace]}, [], []}}}]}
    ]
    {ex_expr, context} = conv_expr(expr, context)
    {{:try, [], [[do: ex_expr, catch: catch_clauses]]}, context}
  end


  defp conv_type(:any, context) do
    {[{:..., [], Elixir}], context}
  end


  defp conv_type(:tuple, :any, context) do
    {{:tuple, [], []}, context}
  end

  defp conv_type(:tuple, params, context) do
    {ex_params, context} = conv_list(params, context)
    {{:{}, [], ex_params}, context}
  end

  defp conv_type(:list, [], context) do
    {{:list, [], []}, context}
  end

  defp conv_type(:list, [type], context) do
    {ex_type, context} = conv_expr(type, context)
    {{:list, [], [ex_type]}, context}
  end

  defp conv_type(nil, [], context) do
    {[], context}
  end

  defp conv_type(:range, [from, to], context) do
    {ex_from, context} = conv_expr(from, context)
    {ex_to, context} = conv_expr(to, context)
    {{:.., @import_kernel_metadata, [ex_from, ex_to]}, context}
  end

  defp conv_type(:binary, [{:integer, _, 0}, {:integer, _, 0}], context) do
    {{:<<>>, [], []}, context}
  end

  defp conv_type(:binary, [m, {:integer, _, 0}], context) do
    {ex_m, context} = conv_expr(m, context)
    {{:<<>>, [], [{:::, [], [{:_, [], Elixir}, ex_m]}]}, context}
  end

  defp conv_type(:binary, [{:integer, _, 0}, n], context) do
    {ex_n, context} = conv_expr(n, context)
    {{:<<>>, [], [{:::, [], [{:_, [], Elixir}, {:*, @import_kernel_metadata, [{:_, [], Elixir}, ex_n]}]}]}, context}
  end

  defp conv_type(:binary, [m, n], context) do
    {ex_m, context} = conv_expr(m, context)
    {ex_n, context} = conv_expr(n, context)
    {{:<<>>, [], [{:::, [], [{:_, [], Elixir}, ex_m]}, {:::, [], [{:_, [], Elixir}, {:*, @import_kernel_metadata, [{:_, [], Elixir}, ex_n]}]}]}, context}
  end

  defp conv_type(:fun, [args, result], context) do
    {ex_args, context} = conv_expr(args, context)
    {ex_result, context} = conv_expr(result, context)
    {[{:->, [], [ex_args, ex_result]}], context}
  end

  defp conv_type(:product, args, context) do
    conv_list(args, context)
  end

  defp conv_type(:map, :any, context) do
    {{:map, [], []}, context}
  end

  defp conv_type(:map, assocs, context) do
    {ex_assocs, context} = conv_list(assocs, context)
    {{:%{}, [], ex_assocs}, context}
  end

  defp conv_type(:map_field_assoc, [key, value], context) do
    {ex_key, context} = conv_expr(key, context)
    {ex_value, context} = conv_expr(value, context)
    {{ex_key, ex_value}, context}
  end

  defp conv_type(:record, [name | fields], context) do
    {ex_name, context} = conv_expr(name, context)
    {ex_fields, context} = conv_list(fields, context)
    {{:record, [], [ex_name, ex_fields]}, context}
  end

  defp conv_type(:field_type, [name, type], context) do
    {ex_name, context} = conv_expr(name, context)
    {ex_type, context} = conv_expr(type, context)
    {{ex_name, ex_type}, context}
  end

  defp conv_type(:union, args, context) do
    conv_union(args, context)
  end

  defp conv_type(name, params, context) do
    {ex_params, context} = conv_list(params, context)
    {{name, [], ex_params}, context}
  end


  defp conv_type(:map_field_assoc, key, value, context) do
    {ex_key, context} = conv_expr(key, context)
    {ex_value, context} = conv_expr(value, context)
    {{ex_key, ex_value}, context}
  end


  defp conv_union([h | []], context) do
    conv_expr(h, context)
  end

  defp conv_union([h | t], context) do
    {ex_h, context} = conv_expr(h, context)
    {ex_t, context} = conv_union(t, context)
    {{:|, [], [ex_h, ex_t]}, context}
  end


  defp record_field_list(record_name, fields, context) do
    {ex_all_fields, context} = conv_list(fields, context)
    {underscores, ex_fields} = Enum.partition(ex_all_fields, fn
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
        {ex_fields ++ extra_fields, context}
      _ ->
        {ex_fields, context}
    end
  end


  defp bin_generator(elems, arg, context) do
    {elems, [last_elem]} = Enum.split(elems, -1)
    {ex_elems, context} = conv_list(elems, context)
    {ex_last_elem, context} = conv_expr(last_elem, context)
    {ex_arg, context} = conv_expr(arg, context)
    {{:<<>>, [], ex_elems ++ [{:<-, [], [ex_last_elem, ex_arg]}]}, context}
  end


  defp bin_element_expr({:string, _, str}, context) do
    {List.to_string(str), context}
  end
  defp bin_element_expr(val, context) do
    conv_expr(val, context)
  end


  defp bin_element_size({:integer, _, size}, context) do
    {size, context}
  end
  defp bin_element_size(size, context) do
    {ex_size, context} = conv_expr(size, context)
    {{:size, [], [ex_size]}, context}
  end


  defp update_map(base_map, assocs = [{:map_field_exact, _, _, _} | _], context) do
    {exact_assocs, remaining_assocs} = assocs
      |> Enum.split_while(fn
        {:map_field_exact, _, _, _} -> true
        _ -> false
      end)
    {ex_exact_assocs, context} = conv_list(exact_assocs, context)
    new_base = {:%{}, [], [{:|, [], [base_map, ex_exact_assocs]}]}
    update_map(new_base, remaining_assocs, context)
  end

  defp update_map(base_map, assocs = [{:map_field_assoc, _, _, _} | _], context) do
    {inexact_assocs, remaining_assocs} = assocs
      |> Enum.split_while(fn
        {:map_field_assoc, _, _, _} -> true
        _ -> false
      end)
    {ex_inexact_assocs, context} = conv_list(inexact_assocs, context)
    new_base = {
      {:., [], [{:__aliases__, [alias: false], [:Map]}, :merge]},
      [],
      [base_map, {:%{}, [], ex_inexact_assocs}]
    }
    update_map(new_base, remaining_assocs, context)
  end

  defp update_map(base_map, [], context) do
    {base_map, context}
  end


  defp conv_generalized_var(name = << "??" :: binary, _ :: binary >>, context) do
    conv_normal_var(String.to_atom(name), context)
  end

  defp conv_generalized_var(<< "?" :: utf8, name :: binary >>, context) do
    conv_const(String.to_atom(name), context)
  end

  defp conv_generalized_var(name, context) do
    conv_normal_var(String.to_atom(name), context)
  end


  defp conv_normal_var(name, context) do
    {mapped_name, needs_caret, context} = Context.map_variable_name(context, name)
    var = {mapped_name, [], Elixir}
    var = cond do
      Context.is_quoted_var?(context, mapped_name) ->
        {:unquote, [], [var]}
      needs_caret ->
        {:^, [], [var]}
      true ->
        var
    end
    {var, context}
  end


  defp conv_const(:MODULE, context) do
    {{:__MODULE__, [], Elixir}, context}
  end

  defp conv_const(:MODULE_STRING, context) do
    {{{:., [], [{:__aliases__, [alias: false], [:Atom]}, :to_char_list]}, [], [{:__MODULE__, [], Elixir}]}, context}
  end

  defp conv_const(:FILE, context) do
    {{{:., [], [{:__aliases__, [alias: false], [:String]}, :to_char_list]}, [], [{{:., [], [{:__ENV__, [], Elixir}, :file]}, [], []}]}, context}
  end

  defp conv_const(:LINE, context) do
    {{{:., [], [{:__ENV__, [], Elixir}, :line]}, [], []}, context}
  end

  defp conv_const(:MACHINE, context) do
    {'BEAM', context}
  end

  defp conv_const(name, context) do
    macro_name = Context.macro_function_name(context, name, nil)
    if macro_name == nil do
      # TODO: Get the line number into here.
      Utils.handle_error(context, name, "(no such macro)")
    end
    {{macro_name, [], []}, context}
  end


  defp conv_call(func = {:remote, _, _, {:atom, _, _}}, args, context) do
    conv_normal_call(func, args, context)
  end

  defp conv_call({:remote, _, module_expr, func_expr}, args, context) do
    {ex_module, context} = conv_expr(module_expr, context)
    {ex_func, context} = conv_expr(func_expr, context)
    {ex_args, context} = conv_list(args, context)
    {{{:., [], [:erlang, :apply]}, [], [ex_module, ex_func, ex_args]}, context}
  end

  defp conv_call({:atom, _, :record_info}, [{:atom, _, :size}, {:atom, _, rec}], context) do
    # TODO: consider using a semantic name for this.
    size = context
      |> Context.record_field_names(rec)
      |> Enum.count
    {size + 1, context}
  end

  defp conv_call({:atom, _, :record_info}, [{:atom, _, :fields}, {:atom, _, rec}], context) do
    # TODO: consider using a semantic name for this.
    {Context.record_field_names(context, rec), context}
  end

  defp conv_call(func, args, context) do
    conv_normal_call(func, args, context)
  end


  defp conv_normal_call(func, args, context) do
    {ex_func, context} = func_spec(func, args, context)
    {ex_args, context} = conv_list(args, context)
    {{ex_func, [], ex_args}, context}
  end


  defp func_spec(func = {:remote, _, _, _}, _args, context) do
    conv_expr(func, context)
  end

  defp func_spec({:atom, _, func}, args, context) do
    arity = Enum.count(args)
    ex_expr = if Context.is_local_func?(context, func, arity) do
      Context.local_function_name(context, func)
    else
      case Map.get(@autoimport_map, func, nil) do
        nil -> {:., [], [:erlang, func]}
        ex_name -> ex_name
      end
    end
    {ex_expr, context}
  end

  defp func_spec(func = {:var, _, name}, args, context) do
    case Atom.to_string(name) do
      << "?" :: utf8, basename :: binary >> ->
        arity = Enum.count(args)
        func_name = Context.macro_function_name(context, String.to_atom(basename), arity)
        if func_name == nil do
          Utils.handle_error(context, func, "(no such macro)")
        end
        {func_name, context}
      _ ->
        {ex_func, context} = conv_expr(func, context)
        {{:., [], [ex_func]}, context}
    end
  end

  defp func_spec(func, _args, context) do
    {ex_func, context} = conv_expr(func, context)
    {{:., [], [ex_func]}, context}
  end


  defp guard_elem([], result, context) do
    {result, context}
  end
  defp guard_elem([ghead | gtail], result, context) do
    # TODO: Make sure we can get away with conv_expr. Erlang guards can conceivably
    # resolve to a value other than true or false, which for Erlang should
    # fail the guard, but in Elixir will succeed the guard. If this is a
    # problem, the Elixir version might need to compare === true.
    {ex_ghead, context} = conv_expr(ghead, context)
    guard_elem(gtail, guard_combine(result, ex_ghead, :and), context)
  end


  defp guard_combine(nil, rhs, _op) do
    rhs
  end
  defp guard_combine(lhs, rhs, op) do
    {op, @import_kernel_metadata, [lhs, rhs]}
  end


end
