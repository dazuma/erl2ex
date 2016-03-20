
defmodule Erl2ex.Pipeline.ModuleData do


  @moduledoc false

  alias Erl2ex.Pipeline.ModuleData
  alias Erl2ex.Pipeline.Names


  defstruct(
    name: nil,
    forms: [],                    # of {erl_ast, erl_syntax_node}
    auto_export_suffixes: [],     # of string
    exports: MapSet.new,          # of {erl_name, arity} and erl_name
    type_exports: MapSet.new,     # of {name, arity}
    imported_funcs: %{},          # of erl_name => (arity => module)
    local_funcs: MapSet.new,      # of {erl_name, arity}
    record_func_names: %{},       # of rec_name => macro_name
    record_data_names: %{},       # of rec_name => attr_name
    record_fields: %{},           # of rec_name => [{field_name, type_expr}]
    used_attr_names: MapSet.new,  # of elixir_name
    used_func_names: MapSet.new,  # of elixir_name
    func_rename_map: %{},         # of erl_name => elixir_name
    macros: %{},                  # of erl_name => MacroData
    macro_dispatcher: nil,
    func_renamer: nil,
    record_size_macro: nil,
    record_index_macro: nil
  )


  defmodule MacroData do
    @moduledoc false
    defstruct const_name: nil,
              func_name: nil,
              define_tracker: nil,
              requires_init: nil,
              has_func_style_call: false,
              is_redefined: MapSet.new,
              const_expr: nil
  end


  def is_exported?(%ModuleData{exports: exports, auto_export_suffixes: auto_export_suffixes}, name, arity) do
    MapSet.member?(exports, {name, arity}) or
      String.ends_with?(Atom.to_string(name), auto_export_suffixes)
  end


  def is_type_exported?(%ModuleData{type_exports: type_exports}, name, arity) do
    MapSet.member?(type_exports, {name, arity})
  end


  def is_local_func?(%ModuleData{local_funcs: local_funcs}, name, arity) do
    MapSet.member?(local_funcs, {name, arity})
  end


  def binary_bif_requires_qualification?(
    %ModuleData{local_funcs: local_funcs, imported_funcs: imported_funcs},
    func_name)
  do
    is_atom(func_name) and Regex.match?(~r/^[a-z]+$/, Atom.to_string(func_name)) and
      (MapSet.member?(local_funcs, {func_name, 2}) or
        Map.has_key?(Map.get(imported_funcs, func_name, %{}), 2)) and
      not MapSet.member?(Names.elixir_reserved_words, func_name)
  end


  def local_function_name(%ModuleData{func_rename_map: func_rename_map}, name) do
    Map.fetch!(func_rename_map, name)
  end


  def has_local_function_name?(%ModuleData{func_rename_map: func_rename_map}, name) do
    Map.has_key?(func_rename_map, name)
  end


  def local_call_strategy(
    %ModuleData{
      local_funcs: local_funcs,
      imported_funcs: imported_funcs,
      func_rename_map: func_rename_map
    },
    name, arity)
  do
    if MapSet.member?(local_funcs, {name, arity}) do
      mapped_name = Map.fetch!(func_rename_map, name)
      cond do
        not Names.callable_function_name?(mapped_name) ->
          {:apply, mapped_name}
        not Names.local_callable_function_name?(mapped_name)
            or Map.has_key?(imported_funcs, mapped_name) ->
          {:qualify, mapped_name}
        true ->
          {:bare, mapped_name}
      end
    else
      import_info = Map.get(imported_funcs, name, %{})
      {imported, which_module, mapped_name} = case Map.fetch(import_info, arity) do
        {:ok, mod} -> {true, mod, name}
        :error ->
          case Names.check_autoimport(name) do
            {:ok, kernel_func} ->
              {true, Kernel, kernel_func}
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


  def macro_needs_dispatch?(%ModuleData{macros: macros}, name) do
    macro_info = Map.get(macros, name, nil)
    if macro_info == nil do
      false
    else
      macro_info.is_redefined == true or
          macro_info.has_func_style_call and macro_info.func_name == nil
    end
  end


  def macro_function_name(%ModuleData{macros: macros}, name, arity) do
    macro_info = Map.get(macros, name, nil)
    cond do
      macro_info == nil -> nil
      arity == nil -> macro_info.const_name
      true -> macro_info.func_name
    end
  end


  def macro_dispatcher_name(%ModuleData{macro_dispatcher: macro_name}) do
    macro_name
  end


  def macro_eager_replacement(%ModuleData{macros: macros}, name) do
    macro_info = Map.fetch!(macros, name)
    macro_info.const_expr
  end


  def func_renamer_name(%ModuleData{func_renamer: func_renamer}) do
    func_renamer
  end


  def record_size_macro(%ModuleData{record_size_macro: macro_name}) do
    macro_name
  end


  def record_index_macro(%ModuleData{record_index_macro: macro_name}) do
    macro_name
  end


  def record_function_name(%ModuleData{record_func_names: record_func_names}, name) do
    Map.fetch!(record_func_names, name)
  end


  def record_data_attr_name(%ModuleData{record_data_names: record_data_names}, name) do
    Map.fetch!(record_data_names, name)
  end


  def record_field_names(%ModuleData{record_fields: record_fields}, record_name) do
    record_fields
      |> Map.fetch!(record_name)
      |> Enum.map(fn {name, _type} -> name end)
  end


  def map_records(%ModuleData{record_fields: record_fields}, func) do
    record_fields |>
      Enum.map(fn {name, fields} -> func.(name, fields) end)
  end


  def tracking_attr_name(%ModuleData{macros: macros}, name) do
    Map.fetch!(macros, name).define_tracker
  end


  def macros_that_need_init(%ModuleData{macros: macros}) do
    macros |> Enum.filter_map(
      fn
        {_, %MacroData{requires_init: true}} -> true
        _ -> false
      end,
      fn {name, %MacroData{define_tracker: define_tracker}} ->
        {name, define_tracker}
      end)
  end


end
