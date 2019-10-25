# The conversion context describes the "state" of a conversion, holding
# information needed to select names, make variable scoping decisions, decide
# how to call functions and macros, and so forth. It is passed down the
# function tree during conversion and modified as needed.

defmodule Erl2ex.Convert.Context do
  @moduledoc false

  alias Erl2ex.Pipeline.Names
  alias Erl2ex.Pipeline.Utils

  alias Erl2ex.Convert.Context

  defstruct(
    # The ModuleData containing results of module-wide analysis. The contents
    # of this structure should not change during conversion.
    module_data: nil,
    # Path to the current file being converted, as a string, or nil if not
    # known (e.g. because the input is a raw string rather than a file from
    # the file system). Used to display error messages.
    cur_file_path: nil,
    # A set of function names currently in use (hence cannot be reused), as
    # a set of strings.
    used_func_names: MapSet.new(),
    # A map from Erlang variable names to Elixir variable names (both atoms)
    variable_map: %{},
    # A map from the Elixir variable name of a macro formal argument, to the
    # name of a local variable within the macro that contains the "stringified"
    # form of its value. (i.e. for the Erlang ?? operator.) Both are atoms.
    stringification_map: %{},
    # A list of Elixir variable names that need to be unquoted in a macro
    # body, because they are arguments to the macro or computed "stringified"
    # values.
    quoted_variables: [],
    # How many "match" structures the converter has descended into. If this is
    # greater than 1, some variables may need carets when referenced rather
    # than set.
    match_level: 0,
    # True if the converter has descended into a type expression.
    in_type_expr: false,
    # True if the converter has descended into a size expression in a binary.
    in_bin_size_expr: false,
    # True if the converter has descended into a list of function params.
    in_func_params: false,
    # True if the converter has descended into a macro definition.
    in_macro_def: false,
    # True if the converter has descended into a context where macro calls
    # are not allowed, so eager macro replacement should be applied.
    in_eager_macro_replacement: false,
    # The set of Erlang variable names (as atoms) that are being set in the
    # current match.
    match_vars: MapSet.new(),
    # A stack of {vars, exports} tuples where the elements are sets of
    # Erlang variable names as atoms. Used to determine where Erlang variables
    # are declared and exported.
    scopes: [],
    # A map of {macro_name, arity} tuple to MapSet of argument indexes,
    # specifying which arguments are exported from the macro to its calling
    # environment.
    macro_exports: %{},
    # A list of {MapSet, Map} tuples used to build macro_exports during macro
    # definition. The MapSet is a running set of exported argument indexes.
    # The Map maps from argument name (as an atom) to its 0-based index.
    macro_export_collection_stack: [],
    # A map from Erlang record name (as an atom) to list of
    # {field_name, field_type} for the fields, in order, where the field_type
    # is the Elixir form of the type.
    record_types: %{},
    # A running list of {field_name, field_type} for the record currently
    # being defined.
    cur_record_types: []
  )

  # Populate a basic context for the module.

  def build(module_data, opts) do
    %Context{
      module_data: module_data,
      cur_file_path: Keyword.get(opts, :cur_file_path, nil),
      used_func_names: module_data.used_func_names
    }
  end

  # Set information about the local variables for the current form.
  # The expr is an Erlang AST of the form body. The macro_args should be
  # present if this is a macro definition, and is a list of the argument
  # names as atoms.

  def set_variable_maps(context, expr, macro_args \\ []) do
    {variable_map, stringification_map} = compute_var_maps(context, expr, macro_args)

    quoted_vars =
      macro_args
      |> Enum.map(&Map.fetch!(variable_map, &1))

    %Context{
      context
      | quoted_variables: quoted_vars ++ Map.values(stringification_map),
        variable_map: variable_map,
        stringification_map: stringification_map
    }
  end

  # Reset the local variable info when exiting a form definition.

  def clear_variable_maps(context) do
    %Context{context | quoted_variables: [], variable_map: %{}, stringification_map: %{}}
  end

  # Get the current variable name map (i.e. Erlang to Elixir names)

  def get_variable_map(%Context{variable_map: variable_map}), do: variable_map

  # Begin collecting info on variables that the current macro exports. You
  # must pass in the list of arguments of the macro.

  def start_macro_export_collection(context, args) do
    index_map = args |> Enum.with_index() |> Enum.into(%{})
    collector = {MapSet.new(), index_map}
    %Context{context | macro_export_collection_stack: [collector | context.macro_export_collection_stack]}
  end

  # Suspend collection of exported variables for the macro, due to an internal
  # macro or function call.

  def suspend_macro_export_collection(context) do
    %Context{context | macro_export_collection_stack: [{MapSet.new(), nil} | context.macro_export_collection_stack]}
  end

  # Resume collection of exported variables for the macro, after suspension.

  def resume_macro_export_collection(context) do
    %Context{context | macro_export_collection_stack: tl(context.macro_export_collection_stack)}
  end

  # Finish collecting macro export information, and set it for the given macro.

  def finish_macro_export_collection(context, name, arity) do
    [{indexes, _} | macro_export_collection_stack] = context.macro_export_collection_stack
    macro_exports = context.macro_exports |> Map.put({name, arity}, indexes)
    %Context{context | macro_exports: macro_exports, macro_export_collection_stack: macro_export_collection_stack}
  end

  # Add a variable that may be exported from the current macro. It is exported
  # if it is present in the macro args.

  def add_macro_export(context, erl_var) do
    case context.macro_export_collection_stack do
      [{_indexes, nil} | _tail] ->
        context

      [{indexes, index_map} | stack_tail] ->
        case Map.fetch(index_map, erl_var) do
          {:ok, index} ->
            %Context{context | macro_export_collection_stack: [{MapSet.put(indexes, index), index_map} | stack_tail]}

          :error ->
            context
        end

      [] ->
        context
    end
  end

  # Get the MapSet of indexes of the arguments exported by the given macro.

  def get_macro_export_indexes(%Context{macro_exports: macro_exports}, name, arity) do
    Map.fetch!(macro_exports, {name, arity})
  end

  # Descend into the LHS of a match. Pass true for in_func_params if we are
  # parsing function arguments.

  def push_match_level(
        %Context{
          match_level: old_match_level,
          in_func_params: old_in_func_params
        } = context,
        in_func_params
      ) do
    %Context{context | match_level: old_match_level + 1, in_func_params: old_in_func_params or in_func_params}
  end

  # Finish a match LHS

  def pop_match_level(
        %Context{
          scopes: scopes,
          match_vars: match_vars,
          match_level: old_match_level
        } = context
      ) do
    if old_match_level == 1 do
      [{top_vars, top_exports} | other_scopes] = scopes
      top_vars = MapSet.union(top_vars, match_vars)

      %Context{
        context
        | match_level: old_match_level - 1,
          in_func_params: false,
          scopes: [{top_vars, top_exports} | other_scopes],
          match_vars: MapSet.new()
      }
    else
      %Context{context | match_level: old_match_level - 1}
    end
  end

  # Begin processing a type expression.

  def set_type_expr_mode(context) do
    %Context{context | in_type_expr: true, in_eager_macro_replacement: true}
  end

  # Finish processing a type expression.

  def clear_type_expr_mode(context) do
    %Context{context | in_type_expr: false, in_eager_macro_replacement: false}
  end

  # Start a variable scope. This happens when descending into a function or
  # macro definition, or a control structure. Begin collecting of variables
  # bound in the scope and variables exported.

  def push_scope(%Context{scopes: scopes} = context) do
    %Context{context | scopes: [{MapSet.new(), MapSet.new()} | scopes]}
  end

  # End a variable scope. If there are exports, add them to the next outer
  # scope.

  def pop_scope(%Context{scopes: [_h]} = context) do
    %Context{context | scopes: []}
  end

  def pop_scope(%Context{scopes: [{top_vars, _top_exports}, {next_vars, next_exports} | t]} = context) do
    next_exports = MapSet.union(next_exports, top_vars)
    %Context{context | scopes: [{next_vars, next_exports} | t]}
  end

  # Clear exports. Used by structures that do not export variables.

  def clear_exports(%Context{scopes: [{top_vars, _top_exports} | t]} = context) do
    %Context{context | scopes: [{top_vars, MapSet.new()} | t]}
  end

  def clear_exports(%Context{scopes: []} = context) do
    context
  end

  # Apply the current exports to the current scope.

  def apply_exports(%Context{scopes: [{top_vars, top_exports} | t]} = context) do
    top_vars = MapSet.union(top_vars, top_exports)
    %Context{context | scopes: [{top_vars, MapSet.new()} | t]}
  end

  def apply_exports(%Context{scopes: []} = context) do
    context
  end

  # Determine whether the given Elixir variable name should be unquoted
  # in a macro body.

  def is_quoted_var?(%Context{quoted_variables: quoted_variables}, name) do
    Enum.member?(quoted_variables, name)
  end

  # Determine whether the given Elixir variable name should be unhygenized
  # (i.e. have the "var!" macro applied) when in a macro body.

  def is_unhygenized_var?(
        %Context{
          macro_export_collection_stack: macro_export_collection_stack,
          quoted_variables: quoted_variables
        },
        name
      ) do
    not Enum.empty?(macro_export_collection_stack) and
      elem(hd(macro_export_collection_stack), 1) != nil and
      not Enum.member?(quoted_variables, name)
  end

  # Generate an Elixir macro name for the given Erlang macro, in the case when
  # the macro needs to be dispatched due to redefinition.

  def generate_macro_name(%Context{used_func_names: used_func_names} = context, name, arity) do
    prefix = if arity == nil, do: "erlconst", else: "erlmacro"
    func_name = Utils.find_available_name(name, used_func_names, prefix)
    context = %Context{context | used_func_names: MapSet.put(used_func_names, func_name)}
    {func_name, context}
  end

  # Given an Erlang variable name, return the Elixir variable name.

  def map_variable_name(context, name) do
    case Map.fetch(context.variable_map, name) do
      {:ok, mapped_name} ->
        if not context.in_bin_size_expr and context.match_level > 0 and name != :_ do
          needs_caret = not context.in_func_params and variable_seen?(context.scopes, name)

          context =
            if needs_caret do
              context
            else
              %Context{context | match_vars: MapSet.put(context.match_vars, name)}
            end

          {:normal_var, mapped_name, needs_caret, context}
        else
          {:normal_var, mapped_name, false, context}
        end

      :error ->
        if context.in_type_expr do
          {:unknown_type_var, context}
        else
          {:unknown_var, context}
        end
    end
  end

  # Enter a size expression in a binary literal.

  def start_bin_size_expr(context) do
    %Context{context | in_bin_size_expr: true}
  end

  # Exit a size expression in a binary literal.

  def finish_bin_size_expr(context) do
    %Context{context | in_bin_size_expr: false}
  end

  # Returns the current file path, for display in error messages.

  def cur_file_path_for_display(%Context{cur_file_path: nil}), do: "(Unknown source file)"

  def cur_file_path_for_display(%Context{cur_file_path: path}), do: path

  # Enter a list of record fields and begin recording types.

  def start_record_types(context) do
    %Context{context | cur_record_types: [], in_eager_macro_replacement: true}
  end

  # Add a record field and type to the current definition.

  def add_record_type(context, field, type) do
    %Context{context | cur_record_types: [{field, type} | context.cur_record_types]}
  end

  # Exit a list of record fields. Save the accumulated field info under the
  # given record name.

  def finish_record_types(context, name) do
    %Context{
      context
      | record_types: Map.put(context.record_types, name, Enum.reverse(context.cur_record_types)),
        cur_record_types: [],
        in_eager_macro_replacement: false
    }
  end

  # Get the list of record fields, as a list of {field_name, elixir_type},
  # for the given Erlang record name.

  def get_record_types(%Context{record_types: record_types}, name) do
    Map.fetch!(record_types, name)
  end

  # Report an error for an unrecognized Erlang expression.

  def handle_error(context, expr, ast_context \\ nil) do
    ast_context = if ast_context, do: " #{ast_context}", else: ""

    raise CompileError,
      file: cur_file_path_for_display(context),
      line: find_error_line(expr),
      description: "Unrecognized Erlang expression#{ast_context}: #{inspect(expr)}"
  end

  # Extract the line number from the given Erlang AST node.

  defp find_error_line(expr) when is_tuple(expr) and tuple_size(expr) >= 3, do: elem(expr, 1)
  defp find_error_line([expr | _]), do: find_error_line(expr)
  defp find_error_line(_), do: :unknown

  # Collect information about the local variables for the given Erlang
  # expression.

  defp compute_var_maps(context, expr, extra_omits) do
    {normal_vars, _consts, stringified_args} =
      expr
      |> collect_variable_names(MapSet.new())
      |> MapSet.union(extra_omits |> Enum.into(MapSet.new()))
      |> classify_var_names()

    all_names = MapSet.union(context.used_func_names, Names.elixir_reserved_words())

    {variables_map, all_names} =
      normal_vars
      |> Enum.reduce({%{}, all_names}, &map_variables/2)

    {stringification_map, variables_map, _all_names} =
      stringified_args
      |> Enum.reduce({%{}, variables_map, all_names}, &map_stringification/2)

    {variables_map, stringification_map}
  end

  # Given an Erlang expression and a set, adds any variable names to the set.

  defp collect_variable_names({:var, _, var}, var_names), do: MapSet.put(var_names, var)

  defp collect_variable_names({:ann_type, _, [_var, type]}, var_names), do: collect_variable_names(type, var_names)

  defp collect_variable_names(tuple, var_names) when is_tuple(tuple),
    do: collect_variable_names(Tuple.to_list(tuple), var_names)

  defp collect_variable_names(list, var_names) when is_list(list),
    do: list |> Enum.reduce(var_names, &collect_variable_names/2)

  defp collect_variable_names(_, var_names), do: var_names

  # Given a set of variable names, return a tuple of three sets: normal
  # names, names of macros (beginning with a single question mark), and names
  # of stringification invocations (beginning with two question marks).

  defp classify_var_names(var_names) do
    groups =
      var_names
      |> Enum.group_by(fn var ->
        name = var |> Atom.to_string()

        cond do
          String.starts_with?(name, "??") -> :stringification
          String.starts_with?(name, "?") -> :const
          true -> :normal
        end
      end)

    {
      Map.get(groups, :normal, []),
      Map.get(groups, :const, []),
      Map.get(groups, :stringification, [])
    }
  end

  # For a variable that represents a stringifcation, update the variable
  # collections.

  defp map_stringification(stringified_arg, {stringification_map, variables_map, all_names}) do
    if Map.has_key?(stringification_map, stringified_arg) do
      {stringification_map, variables_map, all_names}
    else
      arg_name =
        stringified_arg
        |> Atom.to_string()
        |> String.trim_leading("?")
        |> String.to_atom()

      mapped_arg = Map.fetch!(variables_map, arg_name)

      mangled_name =
        mapped_arg
        |> Utils.find_available_name(all_names, "str", 1)

      variables_map = Map.put(variables_map, stringified_arg, mangled_name)
      stringification_map = Map.put(stringification_map, mapped_arg, mangled_name)
      all_names = MapSet.put(all_names, mangled_name)
      {stringification_map, variables_map, all_names}
    end
  end

  # For a variable that represents a normal variable, update the variable
  # collections.

  defp map_variables(var_name, {variables_map, all_names}) do
    if Map.has_key?(variables_map, var_name) do
      {variables_map, all_names}
    else
      mapped_name =
        var_name
        |> Atom.to_string()
        |> Utils.lower_str()
        |> Utils.find_available_name(all_names, "var", 0)

      variables_map = Map.put(variables_map, var_name, mapped_name)
      all_names = MapSet.put(all_names, mapped_name)
      {variables_map, all_names}
    end
  end

  # Returns true if the given variable has been seen in the given scope stack.

  defp variable_seen?([], _name), do: false

  defp variable_seen?([{scopes_h, _} | scopes_t], name) do
    if MapSet.member?(scopes_h, name) do
      true
    else
      variable_seen?(scopes_t, name)
    end
  end
end
