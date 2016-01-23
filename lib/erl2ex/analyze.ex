
defmodule Erl2ex.Analyze do

  @moduledoc false

  alias Erl2ex.AnalyzedFunc
  alias Erl2ex.AnalyzedImport
  alias Erl2ex.AnalyzedType
  alias Erl2ex.AnalyzedMacro
  alias Erl2ex.AnalyzedRecord
  alias Erl2ex.AnalyzedModule

  alias Erl2ex.Utils


  # This is a map of Erlang BIFs to equivalent Elixir Kernel functions.
  @autoimport_map %{
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
  }


  # These names are allowed as names of functions or variables, but clash with
  # Elixir special forms.
  # The converter will allow variables with these names, but will attempt to
  # rename private functions. Exported functions will not be renamed, and will
  # be defined normally, but calling them will require full qualification.
  @elixir_special_forms [
    :alias,
    :case,
    :cond,
    :for,
    :import,
    :quote,
    :receive,
    :require,
    :super,
    :try,
    :unquote,
    :unquote_splicing,
    :with
  ] |> Enum.into(MapSet.new)


  # These names are allowed as names of functions or variables, but clash with
  # auto-imported functions/macros from Kernel.
  # The converter will allow variables with these names, but will attempt to
  # rename private functions. Exported functions will not be renamed, and will
  # be defined normally, but calling them (and calling the Kernel functions of
  # the same name) will require full qualification.
  @elixir_auto_imports %{
    abs: [1],
    alias!: [1],
    and: [2],
    apply: [2, 3],
    binary_part: [3],
    binding: [1],
    bit_size: [1],
    byte_size: [1],
    def: [2],
    defdelegate: [2],
    defexception: [1],
    defimpl: [3],
    defmacro: [2],
    defmacrop: [2],
    "defmodule": [2],
    defoverridable: [1],
    defp: [2],
    defprotocol: [2],
    defstruct: [1],
    destructure: [2],
    div: [2],
    elem: [2],
    exit: [1],
    function_exported?: [3],
    get_and_update_in: [2, 3],
    get_in: [2],
    hd: [1],
    if: [2],
    in: [2],
    inspect: [2],
    is_atom: [1],
    is_binary: [1],
    is_bitstring: [1],
    is_boolean: [1],
    is_float: [1],
    is_function: [1, 2],
    is_integer: [1],
    is_list: [1],
    is_map: [1],
    is_nil: [1],
    is_number: [1],
    is_pid: [1],
    is_port: [1],
    is_reference: [1],
    is_tuple: [1],
    length: [1],
    macro_exported?: [3],
    make_ref: [0],
    map_size: [1],
    match?: [2],
    max: [2],
    min: [2],
    node: [0, 1],
    not: [1],
    or: [2],
    put_elem: [3],
    put_in: [2, 3],
    raise: [1, 2],
    rem: [2],
    reraise: [2, 3],
    round: [1],
    self: [0],
    send: [2],
    sigil_C: [2],
    sigil_R: [2],
    sigil_S: [2],
    sigil_W: [2],
    sigil_c: [2],
    sigil_r: [2],
    sigil_s: [2],
    sigil_w: [2],
    spawn: [1, 3],
    spawn_link: [1, 3],
    spawn_monitor: [1, 3],
    struct: [2],
    struct!: [2],
    throw: [1],
    tl: [1],
    to_char_list: [1],
    to_string: [1],
    trunc: [1],
    tuple_size: [1],
    unless: [2],
    update_in: [2, 3],
    use: [2],
    var!: [2],
  }


  def module(erl_module, _opts \\ []) do
    analysis = build_base_analysis(erl_module)
    analysis = Enum.reduce(erl_module.exports, analysis, &collect_exports/2)
    analysis = Enum.reduce(erl_module.forms, analysis, &collect_imports/2)
    analysis = Enum.reduce(erl_module.forms, analysis, &collect_func_info/2)
    analysis = Enum.reduce(analysis.funcs, analysis, &assign_func_names/2)
    analysis = Enum.reduce(erl_module.type_exports, analysis, &collect_type_exports/2)
    analysis = Enum.reduce(erl_module.forms, analysis, &collect_attr_info/2)
    analysis = Enum.reduce(erl_module.forms, analysis, &collect_record_info/2)
    analysis = Enum.reduce(erl_module.forms, analysis, &collect_macro_info/2)
    analysis = Enum.reduce(erl_module.specs, analysis, &collect_specs/2)
    analysis
  end


  def is_exported?(%AnalyzedModule{funcs: funcs}, name, arity) do
    info = Map.get(funcs, name, %AnalyzedFunc{})
    Map.get(info.arities, arity, false)
  end


  def is_type_exported?(%AnalyzedModule{types: types}, name, arity) do
    info = Map.get(types, name, %AnalyzedType{})
    Map.get(info.arities, arity, false)
  end


  def is_local_func?(%AnalyzedModule{funcs: funcs}, name, arity) do
    info = Map.get(funcs, name, %AnalyzedFunc{})
    Map.has_key?(info.arities, arity)
  end


  def local_function_name(%AnalyzedModule{funcs: funcs}, name) do
    Map.fetch!(funcs, name).func_name
  end


  def local_call_strategy(%AnalyzedModule{funcs: funcs, imports: imports}, name, arity) do
    func_info = Map.get(funcs, name, %AnalyzedFunc{})
    if Map.has_key?(func_info.arities, arity) do
      mapped_name = func_info.func_name
      cond do
        not is_legal_function_name(mapped_name) or Utils.is_reserved_word(mapped_name) ->
          {:apply, mapped_name}
        MapSet.member?(@elixir_special_forms, mapped_name) or Map.has_key?(imports, mapped_name) ->
          {:qualify, mapped_name}
        true ->
          {:bare, mapped_name}
      end
    else
      import_info = Map.get(imports, name, %AnalyzedImport{})
      {imported, which_module, mapped_name} = case Map.fetch(import_info.arities, arity) do
        {:ok, mod} -> {true, mod, name}
        :error ->
          case Map.fetch(@autoimport_map, name) do
            {:ok, kernel_func} ->
              {true, Kernel, kernel_func}
            :error ->
              {false, :erlang, name}
          end
      end
      cond do
        not is_legal_function_name(mapped_name) or Utils.is_reserved_word(mapped_name) ->
          {:apply, which_module, mapped_name}
        MapSet.member?(@elixir_special_forms, mapped_name) or !imported ->
          {:qualify, which_module, mapped_name}
        true ->
          {:bare, which_module, mapped_name}
      end
    end
  end


  def macro_needs_dispatch?(%AnalyzedModule{macros: macros}, name) do
    macro_info = Map.get(macros, name, nil)
    if macro_info == nil do
      false
    else
      macro_info.is_redefined == true or
          macro_info.has_func_style_call and macro_info.func_name == nil
    end
  end


  def macro_function_name(%AnalyzedModule{macros: macros}, name, arity) do
    macro_info = Map.get(macros, name, nil)
    cond do
      macro_info == nil -> nil
      arity == nil -> macro_info.const_name
      true -> macro_info.func_name
    end
  end


  def macro_dispatcher_name(%AnalyzedModule{macro_dispatcher: macro_name}) do
    macro_name
  end


  def record_size_macro(%AnalyzedModule{record_size_macro: macro_name}) do
    macro_name
  end


  def record_index_macro(%AnalyzedModule{record_index_macro: macro_name}) do
    macro_name
  end


  def record_function_name(%AnalyzedModule{records: records}, name) do
    Map.fetch!(records, name).func_name
  end


  def record_data_attr_name(%AnalyzedModule{records: records}, name) do
    Map.fetch!(records, name).data_name
  end


  def record_field_names(%AnalyzedModule{records: records}, record_name) do
    Map.fetch!(records, record_name).fields
  end


  def map_records(%AnalyzedModule{records: records}, func) do
    records |>
      Enum.map(fn {name, %AnalyzedRecord{fields: fields}} ->
        func.(name, fields)
      end)
  end


  def tracking_attr_name(%AnalyzedModule{macros: macros}, name) do
    Map.fetch!(macros, name).define_tracker
  end


  def specs_for_func(%AnalyzedModule{specs: specs}, name) do
    Map.get(specs, name, %Erl2ex.ErlSpec{name: name})
  end


  def macros_that_need_init(%AnalyzedModule{macros: macros}) do
    macros |> Enum.filter_map(
      fn
        {_, %AnalyzedMacro{requires_init: true}} -> true
        _ -> false
      end,
      fn {name, %AnalyzedMacro{define_tracker: define_tracker}} ->
        {name, define_tracker}
      end)
  end


  defp build_base_analysis(erl_module) do
    default_imports = @elixir_auto_imports
      |> Enum.map(fn {name, arities} ->
        arity_info = arities
          |> Enum.map(fn arity -> {arity, Kernel} end)
          |> Enum.into(%{})
        {name, %AnalyzedImport{arities: arity_info}}
      end)
      |> Enum.into(%{})

    %AnalyzedModule{
      erl_module: erl_module,
      imports: default_imports,
      used_func_names: default_imports |> Map.keys |> Enum.into(MapSet.new)
    }
  end


  defp collect_exports({name, arity}, analysis) do
    func_info = Map.get(analysis.funcs, name, %AnalyzedFunc{})
    func_info = %AnalyzedFunc{func_info |
      arities: Map.put(func_info.arities, arity, true),
      is_exported: true,
    }
    %AnalyzedModule{analysis |
      funcs: Map.put(analysis.funcs, name, func_info)
    }
  end


  defp collect_imports(%Erl2ex.ErlImport{module: from_module, funcs: funcs}, analysis) do
    Enum.reduce(funcs, analysis, &(add_import_info(from_module, &1, &2)))
  end
  defp collect_imports(_, analysis), do: analysis

  defp add_import_info(from_module, {name, arity}, analysis) do
    import_info = Map.get(analysis.imports, name, %AnalyzedImport{})
    import_info = %AnalyzedImport{import_info |
      arities: Map.put(import_info.arities, arity, from_module)
    }
    %AnalyzedModule{analysis |
      imports: Map.put(analysis.imports, name, import_info),
      used_func_names: MapSet.put(analysis.used_func_names, name)
    }
  end


  defp collect_func_info(%Erl2ex.ErlFunc{name: name, arity: arity}, analysis) do
    add_func_info({name, arity}, analysis)
  end
  defp collect_func_info(_, analysis), do: analysis

  defp add_func_info({name, arity}, analysis) do
    func_info = Map.get(analysis.funcs, name, %AnalyzedFunc{})
    func_info = %AnalyzedFunc{func_info |
      arities: Map.put_new(func_info.arities, arity, false)
    }
    used_func_names = analysis.used_func_names
    if func_info.func_name == {} do
      bare_name_ok = is_legal_function_name(name) and
          not Utils.is_reserved_word(name) and
          not MapSet.member?(@elixir_special_forms, name) and
          not Map.has_key?(analysis.imports, name)
      if func_info.is_exported or bare_name_ok do
        func_info = %AnalyzedFunc{func_info |
          func_name: name,
        }
        used_func_names = MapSet.put(used_func_names, name)
      end
    end
    %AnalyzedModule{analysis |
      funcs: Map.put(analysis.funcs, name, func_info),
      used_func_names: used_func_names
    }
  end


  defp is_legal_function_name(name) do
    Regex.match?(~r/^[_a-z]\w*$/, Atom.to_string(name))
  end


  defp assign_func_names({name, info = %AnalyzedFunc{func_name: {}}}, analysis) do
    mangled_name = Regex.replace(~r/\W/, Atom.to_string(name), "_")
    mangled_name = mangled_name
      |> Utils.find_available_name(analysis.used_func_names, "func")
    info = %AnalyzedFunc{info | func_name: mangled_name}
    %AnalyzedModule{analysis |
      funcs: Map.put(analysis.funcs, name, info),
      used_func_names: MapSet.put(analysis.used_func_names, mangled_name)
    }
  end
  defp assign_func_names(_, analysis), do: analysis


  defp collect_type_exports({name, arity}, analysis) do
    type_info = Map.get(analysis.types, name, %AnalyzedType{})
    type_info = %AnalyzedType{type_info |
      arities: Map.put(type_info.arities, arity, true)
    }
    %AnalyzedModule{analysis |
      types: Map.put(analysis.types, name, type_info)
    }
  end


  defp collect_attr_info(%Erl2ex.ErlAttr{name: name}, analysis) do
    %AnalyzedModule{analysis |
      used_attr_names: MapSet.put(analysis.used_attr_names, name)
    }
  end
  defp collect_attr_info(_, analysis), do: analysis


  defp collect_record_info(%Erl2ex.ErlRecord{name: name, fields: fields}, analysis) do
    macro_name = Utils.find_available_name(name, analysis.used_func_names, "erlrecord")
    data_name = Utils.find_available_name(name, analysis.used_attr_names, "erlrecordfields")
    record_info = %AnalyzedRecord{
      func_name: macro_name,
      data_name: data_name,
      fields: fields |> Enum.map(&extract_record_field_name/1)
    }
    %AnalyzedModule{analysis |
      used_func_names: MapSet.put(analysis.used_func_names, macro_name),
      used_attr_names: MapSet.put(analysis.used_attr_names, data_name),
      records: Map.put(analysis.records, name, record_info)
    }
  end
  defp collect_record_info(%Erl2ex.ErlFunc{clauses: clauses}, analysis) do
    detect_record_query_presence(clauses, analysis)
  end
  defp collect_record_info(%Erl2ex.ErlDefine{replacement: replacement}, analysis) do
    detect_record_query_presence(replacement, analysis)
  end
  defp collect_record_info(_, analysis), do: analysis

  defp extract_record_field_name({:typed_record_field, record_field, _type}), do:
    extract_record_field_name(record_field)
  defp extract_record_field_name({:record_field, _, {:atom, _, name}}), do: name
  defp extract_record_field_name({:record_field, _, {:atom, _, name}, _}), do: name

  defp detect_record_query_presence({:call, _, {:atom, _, :record_info}, [{:atom, _, :size}, _]}, analysis), do:
    set_record_size_macro(analysis)
  defp detect_record_query_presence({:record_index, _, _, _}, analysis), do:
    set_record_index_macro(analysis)
  defp detect_record_query_presence(tuple, analysis) when is_tuple(tuple), do:
    detect_record_query_presence(Tuple.to_list(tuple), analysis)
  defp detect_record_query_presence(list, analysis) when is_list(list), do:
    list |> Enum.reduce(analysis, &detect_record_query_presence/2)
  defp detect_record_query_presence(_, analysis), do: analysis


  defp set_record_size_macro(analysis = %AnalyzedModule{record_size_macro: nil, used_func_names: used_func_names}) do
    macro_name = Utils.find_available_name("erlrecordsize", used_func_names)
    %AnalyzedModule{analysis |
      record_size_macro: macro_name,
      used_func_names: MapSet.put(used_func_names, macro_name)
    }
  end
  defp set_record_size_macro(analysis), do: analysis

  defp set_record_index_macro(analysis = %AnalyzedModule{record_index_macro: nil, used_func_names: used_func_names}) do
    macro_name = Utils.find_available_name("erlrecordindex", used_func_names)
    %AnalyzedModule{analysis |
      record_index_macro: macro_name,
      used_func_names: MapSet.put(used_func_names, macro_name)
    }
  end
  defp set_record_index_macro(analysis), do: analysis


  defp collect_macro_info(%Erl2ex.ErlDefine{name: name, args: args, replacement: replacement}, analysis) do
    macro = Map.get(analysis.macros, name, %AnalyzedMacro{})
    requires_init = update_requires_init(macro.requires_init, false)
    macro = %AnalyzedMacro{macro | requires_init: requires_init}
    next_is_redefined = update_is_redefined(macro.is_redefined, args)
    analysis = update_macro_info(macro, next_is_redefined, args, name, analysis)
    detect_func_style_call(replacement, analysis)
  end

  defp collect_macro_info(%Erl2ex.ErlDirective{name: name}, analysis) when name != nil do
    macro = Map.get(analysis.macros, name, %AnalyzedMacro{})
    if macro.define_tracker == nil do
      tracker_name = Utils.find_available_name(name, analysis.used_attr_names, "defined")
      macro = %AnalyzedMacro{macro |
        define_tracker: tracker_name,
        requires_init: update_requires_init(macro.requires_init, true)
      }
      %AnalyzedModule{analysis |
        macros: Map.put(analysis.macros, name, macro),
        used_attr_names: MapSet.put(analysis.used_attr_names, tracker_name)
      }
    else
      analysis
    end
  end

  defp collect_macro_info(%Erl2ex.ErlFunc{clauses: clauses}, analysis) do
    detect_func_style_call(clauses, analysis)
  end

  defp collect_macro_info(_, analysis), do: analysis


  defp detect_func_style_call(
    {:call, _, {:var, _, name}, _},
    %AnalyzedModule{
      macros: macros,
      macro_dispatcher: macro_dispatcher,
      used_func_names: used_func_names
    } = analysis)
  do
    case Atom.to_string(name) do
      << "?" :: utf8, basename :: binary >> ->
        macro = Map.get(macros, String.to_atom(basename), %AnalyzedMacro{})
        macro = %AnalyzedMacro{macro | has_func_style_call: true}
        if macro_dispatcher == nil and macro.func_name == nil do
          macro_dispatcher = Utils.find_available_name("erlmacro", used_func_names)
          used_func_names = used_func_names |> MapSet.put(macro_dispatcher)
        end
        %AnalyzedModule{analysis |
          macros: Map.put(macros, name, macro),
          macro_dispatcher: macro_dispatcher,
          used_func_names: used_func_names
        }
      _ ->
        analysis
    end
  end

  defp detect_func_style_call(tuple, analysis) when is_tuple(tuple), do:
    detect_func_style_call(Tuple.to_list(tuple), analysis)

  defp detect_func_style_call(list, analysis) when is_list(list), do:
    list |> Enum.reduce(analysis, &detect_func_style_call/2)

  defp detect_func_style_call(_, analysis), do: analysis


  defp update_macro_info(
    %AnalyzedMacro{
      const_name: const_name,
      is_redefined: true
    } = macro,
    true, nil, name,
    %AnalyzedModule{
      macros: macros,
      used_attr_names: used_attr_names
    } = analysis)
  do
    {const_name, used_attr_names} = update_macro_name(name, const_name, used_attr_names, "erlconst")
    macro = %AnalyzedMacro{macro |
      const_name: const_name
    }
    %AnalyzedModule{analysis |
      macros: Map.put(macros, name, macro),
      used_attr_names: used_attr_names
    }
  end

  defp update_macro_info(
    %AnalyzedMacro{
      func_name: func_name,
      is_redefined: true
    } = macro,
    true, _args, name,
    %AnalyzedModule{
      macros: macros,
      used_attr_names: used_attr_names
    } = analysis)
  do
    {func_name, used_attr_names} = update_macro_name(name, func_name, used_attr_names, "erlmacro")
    macro = %AnalyzedMacro{macro |
      func_name: func_name
    }
    %AnalyzedModule{analysis |
      macros: Map.put(macros, name, macro),
      used_attr_names: used_attr_names
    }
  end

  defp update_macro_info(
    %AnalyzedMacro{
      const_name: const_name,
      func_name: func_name
    } = macro,
    true, args, name,
    %AnalyzedModule{
      macros: macros,
      macro_dispatcher: macro_dispatcher,
      used_func_names: used_func_names,
      used_attr_names: used_attr_names
    } = analysis)
  do
    used_func_names = used_func_names
      |> MapSet.delete(const_name)
      |> MapSet.delete(func_name)
    if const_name != nil or args == nil do
      {const_name, used_attr_names} = update_macro_name(name, nil, used_attr_names, "erlconst")
    end
    if func_name != nil or args != nil do
      {func_name, used_attr_names} = update_macro_name(name, nil, used_attr_names, "erlmacro")
    end
    if macro_dispatcher == nil do
      macro_dispatcher = Utils.find_available_name("erlmacro", used_func_names)
      used_func_names = used_func_names |> MapSet.put(macro_dispatcher)
    end
    macro = %AnalyzedMacro{macro |
      is_redefined: true,
      const_name: const_name,
      func_name: func_name
    }
    %AnalyzedModule{analysis |
      macros: Map.put(macros, name, macro),
      macro_dispatcher: macro_dispatcher,
      used_func_names: used_func_names,
      used_attr_names: used_attr_names
    }
  end

  defp update_macro_info(
    %AnalyzedMacro{
      const_name: const_name,
    } = macro,
    is_redefined, nil, name,
    %AnalyzedModule{
      macros: macros,
      used_func_names: used_func_names
    } = analysis)
  do
    {const_name, used_func_names} = update_macro_name(name, const_name, used_func_names, "erlconst")
    macro = %AnalyzedMacro{macro |
      is_redefined: is_redefined,
      const_name: const_name
    }
    %AnalyzedModule{analysis |
      macros: Map.put(macros, name, macro),
      used_func_names: used_func_names
    }
  end

  defp update_macro_info(
    %AnalyzedMacro{
      func_name: func_name,
    } = macro,
    is_redefined, _args, name,
    %AnalyzedModule{
      macros: macros,
      used_func_names: used_func_names
    } = analysis)
  do
    {func_name, used_func_names} = update_macro_name(name, func_name, used_func_names, "erlmacro")
    macro = %AnalyzedMacro{macro |
      is_redefined: is_redefined,
      func_name: func_name
    }
    %AnalyzedModule{analysis |
      macros: Map.put(macros, name, macro),
      used_func_names: used_func_names
    }
  end


  defp update_macro_name(given_name, nil, used_names, prefix) do
    macro_name = Utils.find_available_name(given_name, used_names, prefix)
    used_names = MapSet.put(used_names, macro_name)
    {macro_name, used_names}
  end
  defp update_macro_name(_given_name, cur_name, used_names, _prefix) do
    {cur_name, used_names}
  end


  defp update_requires_init(nil, nval), do: nval
  defp update_requires_init(oval, _nval), do: oval


  defp update_is_redefined(true, _args), do: true
  defp update_is_redefined(set, args) when is_list(args) do
    update_is_redefined(set, Enum.count(args))
  end
  defp update_is_redefined(set, arity) do
    if MapSet.member?(set, arity), do: true, else: MapSet.put(set, arity)
  end


  defp collect_specs(spec = %Erl2ex.ErlSpec{name: name}, analysis), do:
    %AnalyzedModule{analysis | specs: Map.put(analysis.specs, name, spec)}

end
