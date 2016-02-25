
defmodule Erl2ex.Pipeline.ErlSyntax do

  @moduledoc false


  def on_trees1([node1], _default, func), do: func.(node1)
  def on_trees1(_nodes, default, _func), do: handle_default(default)


  def on_trees2([node1, node2], _default, func), do: func.(node1, node2)
  def on_trees2(_nodes, default, _func), do: handle_default(default)


  def on_list_skeleton(list_node, default, func) do
    if :erl_syntax.is_list_skeleton(list_node) do
      func.(:erl_syntax.list_elements(list_node))
    else
      handle_default(default)
    end
  end


  def on_type(tree_node, expected_type, default, func) do
    if :erl_syntax.type(tree_node) == expected_type do
      func.()
    else
      handle_default(default)
    end
  end


  def on_atom(atom_node, default, func) do
    on_type(atom_node, :atom, default, fn ->
      func.(:erl_syntax.atom_value(atom_node))
    end)
  end


  def on_atom_value(atom_node, expected_value, default, func) do
    on_atom(atom_node, default, fn value ->
      if value == expected_value do
        func.()
      else
        handle_default(default)
      end
    end)
  end


  def on_integer(integer_node, default, func) do
    on_type(integer_node, :integer, default, fn ->
      func.(:erl_syntax.integer_value(integer_node))
    end)
  end


  def on_string(string_node, default, func) do
    on_type(string_node, :string, default, fn ->
      func.(string_node |> :erl_syntax.string_value |> List.to_string)
    end)
  end


  def on_tuple(tuple_node, default, func) do
    on_type(tuple_node, :tuple, default, fn ->
      func.(:erl_syntax.tuple_size(tuple_node), :erl_syntax.tuple_elements(tuple_node))
    end)
  end


  def on_arity_qualifier_list(list_node, default, func) do
    on_list_skeleton(list_node, default, fn elem_nodes ->
      elem_nodes |> Enum.reduce(default, fn elem_node, cur_obj ->
        on_type(elem_node, :arity_qualifier, cur_obj, fn ->
          body_node = :erl_syntax.arity_qualifier_body(elem_node)
          arity_node = :erl_syntax.arity_qualifier_argument(elem_node)
          on_atom(body_node, cur_obj, fn name ->
            on_integer(arity_node, cur_obj, fn arity ->
              func.(cur_obj, name, arity)
            end)
          end)
        end)
      end)
    end)
  end


  def on_type_with_arity_list(list_node, default, func) do
    on_list_skeleton(list_node, default, fn elem_nodes ->
      elem_nodes |> Enum.reduce(default, fn elem_node, cur_obj ->
        on_tuple(elem_node, cur_obj, fn
          2, tuple_elem_nodes ->
            [body_node, arity_node] = tuple_elem_nodes
            on_atom(body_node, cur_obj, fn name ->
              on_integer(arity_node, cur_obj, fn arity ->
                func.(cur_obj, name, arity)
              end)
            end)
          _, _ ->
            cur_obj
        end)
      end)
    end)
  end


  def on_attribute(form_node, default, func) do
    if :erl_syntax.type(form_node) == :attribute do
      name_node = :erl_syntax.attribute_name(form_node)
      arg_nodes = :erl_syntax.attribute_arguments(form_node)
      func.(name_node, arg_nodes)
    else
      handle_default(default)
    end
  end


  def on_static_attribute(form_node, default, func) do
    on_attribute(form_node, default, fn name_node, arg_nodes ->
      on_atom(name_node, default, fn name ->
        func.(name, arg_nodes)
      end)
    end)
  end


  def on_attribute_name(form_node, expected_name, default, func) do
    on_attribute(form_node, default, fn name_node, arg_nodes ->
      on_atom_value(name_node, expected_name, default, fn ->
        func.(arg_nodes)
      end)
    end)
  end


  defp handle_default(default) when is_function(default), do: default.()
  defp handle_default(default), do: default


end
