# This data structure is the output of the analyze phase. It includes a bunch
# of information about the module as a whole.

defmodule Erl2ex.Pipeline.ModuleData do
  @moduledoc false

  alias Erl2ex.Pipeline.ModuleData
  alias Erl2ex.Pipeline.Names

  defstruct(
    # Name of the module, as an atom
    name: nil,
    # List of forms, as {erl_ast, erl_syntax_node}
    forms: [],
    # List of function name suffixes that should automatically be exported,
    # as a list of strings.
    auto_export_suffixes: [],
    # Set of Erlang function names to be exported. Each function is
    # represented both as a {name atom, arity integer} tuple and as a
    # bare name atom.
    exports: MapSet.new(),
    # Set of Erlang types to be exported. Each is represented as a
    # {name atom, arity integer} tuple.
    type_exports: MapSet.new(),
    # A map of imported functions, specifying what module each is imported
    # from. Structure is (name atom => (arity integer => module name atom))
    imported_funcs: %{},
    # A set of the original (Erlang) names of functions defined in this module.
    # The structure is {name atom, arity integer}.
    local_funcs: MapSet.new(),
    # Map of Erlang record name atoms to RecordData.
    records: %{},
    # Set of attribute names (as atoms) that are in use and can no longer
    # be assigned.
    used_attr_names: MapSet.new(),
    # Set of function names (as atoms) that are in use and can no longer
    # be assigned.
    used_func_names: MapSet.new(),
    # Mapping from Erlang to Elixir function names (atom => atom)
    func_rename_map: %{},
    # Map of Erlang macro name atoms to MacroData
    macros: %{},
    # Name of the macro dispatcher as an atom, if needed, or nil if not.
    macro_dispatcher: nil,
    # Name (as an atom) of the Elixir macro that returns record size, or nil
    # if not needed.
    record_size_macro: nil,
    # Name (as an atom) of the Elixir macro that returns record field index,
    # or nil if not needed.
    record_index_macro: nil,
    # True if the is_record BIF is called in this module.
    has_is_record: false
  )

  # A structure of data about a macro.

  defmodule MacroData do
    @moduledoc false
    defstruct(
      # The name of the single no-argument macro in Elixir, if this macro
      # has exactly one no-argument definition. Or nil if this macro has
      # zero or multiple no-argument definitions.
      const_name: nil,
      # The name of the single macro with arguments in Elixir, if this macro
      # has exactly one definition with arguments. Or nil if this macro has
      # zero or multiple such definitions.
      func_name: nil,
      # The name of the Elixir attribute that tracks whether this macro has
      # been defined, or nil if such an attribute is not needed.
      define_tracker: nil,
      # True if this macro is tested for existence (i.e. ifdef) prior to its
      # first definition (which means we need to initialize the define_tracker
      # at the top of the module). False if this macro is defined prior to its
      # first existence test. Or nil if we have no information (which should
      # be treated the same as false).
      requires_init: nil,
      # True if this macro is invoked with arguments.
      has_func_style_call: false,
      # Whether this macro is redefined during the module. If true, we've
      # determined it has been redefined. Otherwise, it will be a set of
      # integers representing the arities of definitions we've seen so far.
      is_redefined: MapSet.new(),
      # If this macro has a single constant defintion, stores the Erlang AST
      # for that definition. Used for cases where we need to inline it.
      const_expr: nil
    )
  end

  # A structure of data about a record.

  defmodule RecordData do
    @moduledoc false
    defstruct(
      # The name of the Elixir macro for this record, as an atom
      func_name: nil,
      # The name of the attribute storing this record's fields
      data_attr_name: nil,
      # The field data, as a list of {name, type} tuples. The name is an atom,
      # and the type is an Erlang type AST.
      fields: []
    )
  end

  # Returns true if the given Erlang function name and arity are exported.

  def is_exported?(%ModuleData{exports: exports, auto_export_suffixes: auto_export_suffixes}, name, arity) do
    MapSet.member?(exports, {name, arity}) or
      String.ends_with?(Atom.to_string(name), auto_export_suffixes)
  end

  # Returns true if the given Erlang type name and arity are exported.

  def is_type_exported?(%ModuleData{type_exports: type_exports}, name, arity) do
    MapSet.member?(type_exports, {name, arity})
  end

  # Returns true if the given Erlang function name and arity is defined in
  # this module.

  def is_local_func?(%ModuleData{local_funcs: local_funcs}, name, arity) do
    MapSet.member?(local_funcs, {name, arity})
  end

  # Returns true if the given function name which is a BIF in Erlang needs
  # qualification in Elixir.

  def binary_bif_requires_qualification?(
        %ModuleData{local_funcs: local_funcs, imported_funcs: imported_funcs},
        func_name
      ) do
    is_atom(func_name) and Regex.match?(~r/^[a-z]+$/, Atom.to_string(func_name)) and
      (MapSet.member?(local_funcs, {func_name, 2}) or
         Map.has_key?(Map.get(imported_funcs, func_name, %{}), 2)) and
      not MapSet.member?(Names.elixir_reserved_words(), func_name)
  end

  # Given an Erlang name for a function in this module, returns the name that
  # should be used in the Elixir module.

  def local_function_name(%ModuleData{func_rename_map: func_rename_map}, name) do
    Map.fetch!(func_rename_map, name)
  end

  # Given a name atom, returns true if it is an Erlang function defined in
  # this module.

  def has_local_function_name?(%ModuleData{func_rename_map: func_rename_map}, name) do
    Map.has_key?(func_rename_map, name)
  end

  # Given a function name/arity that was called without qualification in
  # Erlang, returns some information on how to call it in Elixir. Possible
  # return values are:
  #   * {:apply, local_name_atom}
  #   * {:apply, module_atom, local_name_atom}
  #   * {:qualify, local_name_atom}
  #   * {:qualify, module_atom, local_name_atom}
  #   * {:bare, local_name_atom}
  #   * {:bare, module_atom, local_name_atom}
  # Apply means Kernel.apply must be used.
  # Qualify means Elixir must call Module.func.
  # Bare means Elixir may call the function without qualification.

  def local_call_strategy(
        %ModuleData{
          local_funcs: local_funcs,
          imported_funcs: imported_funcs,
          func_rename_map: func_rename_map
        },
        name,
        arity
      ) do
    if MapSet.member?(local_funcs, {name, arity}) do
      mapped_name = Map.fetch!(func_rename_map, name)

      cond do
        not Names.callable_function_name?(mapped_name) ->
          {:apply, mapped_name}

        not Names.local_callable_function_name?(mapped_name) or
            Map.has_key?(imported_funcs, mapped_name) ->
          {:qualify, mapped_name}

        true ->
          {:bare, mapped_name}
      end
    else
      import_info = Map.get(imported_funcs, name, %{})

      {imported, which_module, mapped_name} =
        case Map.fetch(import_info, arity) do
          {:ok, mod} ->
            {true, mod, name}

          :error ->
            case Names.map_bif(name) do
              {:ok, Kernel, mapped_func} ->
                {true, Kernel, mapped_func}

              {:ok, mapped_mod, mapped_func} ->
                {false, mapped_mod, mapped_func}

              :error ->
                {false, :erlang, name}
            end
        end

      cond do
        not Names.callable_function_name?(mapped_name) ->
          {:apply, which_module, mapped_name}

        not Names.local_callable_function_name?(mapped_name) or not imported ->
          {:qualify, which_module, mapped_name}

        true ->
          {:bare, which_module, mapped_name}
      end
    end
  end

  # Returns true if the given Erlang macro requires the macro dispatcher.

  def macro_needs_dispatch?(%ModuleData{macros: macros}, name) do
    macro_info = Map.get(macros, name, nil)

    if macro_info == nil do
      false
    else
      macro_info.is_redefined == true or
        (macro_info.has_func_style_call and macro_info.func_name == nil)
    end
  end

  # Given an Erlang macro and arity, returns the Elixir macro name.

  def macro_function_name(%ModuleData{macros: macros}, name, arity) do
    macro_info = Map.get(macros, name, nil)

    cond do
      macro_info == nil -> nil
      arity == nil -> macro_info.const_name
      true -> macro_info.func_name
    end
  end

  # Returns the name of the macro dispatcher.

  def macro_dispatcher_name(%ModuleData{macro_dispatcher: macro_name}) do
    macro_name
  end

  # Given a macro with a single constant replacement, returns that replacement
  # as an Erlang AST, or nil if no such replacement exists.

  def macro_eager_replacement(%ModuleData{macros: macros}, name) do
    macro_info = Map.fetch!(macros, name)
    macro_info.const_expr
  end

  # Returns the name of the Elixir macro to call to get a record's size.

  def record_size_macro(%ModuleData{record_size_macro: macro_name}) do
    macro_name
  end

  # Returns the name of the Elixir macro to call to get the index of
  # a record field.

  def record_index_macro(%ModuleData{record_index_macro: macro_name}) do
    macro_name
  end

  # Returns the name of the Elixir record macro for the given Erlang record
  # name.

  def record_function_name(%ModuleData{records: records}, name) do
    record_info = Map.fetch!(records, name)
    record_info.func_name
  end

  # Returns the name of the attribute storing the fields for the given Erlang
  # record name.

  def record_data_attr_name(%ModuleData{records: records}, name) do
    record_info = Map.fetch!(records, name)
    record_info.data_attr_name
  end

  # Returns a list of field names (as atoms) for the given Erlang record name.

  def record_field_names(%ModuleData{records: records}, name) do
    record_info = Map.fetch!(records, name)
    Enum.map(record_info.fields, fn {name, _type} -> name end)
  end

  # Passes the given function to Enum.map over the records. Each function
  # call is passed the Erlang name of the record, and the list of fields
  # as a list of {name, type} tuples, where name is an atom and type is the
  # Erlang type AST.

  def map_records(%ModuleData{records: records}, func) do
    Enum.map(records, fn {name, info} -> func.(name, info.fields) end)
  end

  # Returns the name of the attribute tracking definition of the given
  # Erlang record name.

  def tracking_attr_name(%ModuleData{macros: macros}, name) do
    Map.fetch!(macros, name).define_tracker
  end

  # Returns a list of {name, define_tracker_attribute} for all macros that
  # require init.

  def macros_that_need_init(%ModuleData{macros: macros}) do
    macros
    |> Enum.filter(fn
      {_, %MacroData{requires_init: true}} -> true
      _ -> false
    end)
    |> Enum.map(fn {name, %MacroData{define_tracker: define_tracker}} ->
      {name, define_tracker}
    end)
  end
end
