
defmodule Erl2ex.Convert.Context do

  @moduledoc false

  alias Erl2ex.Convert.Context


  # These are not allowed as names of functions
  @elixir_reserved_words [
    :do,
    :else,
    :end,
    :false,
    :fn,
    :nil,
    :true,
  ] |> Enum.into(HashSet.new)


  defstruct funcs: HashDict.new,
            types: HashDict.new,
            macros: HashDict.new,
            records: HashDict.new,
            used_func_names: HashSet.new,
            used_attr_names: HashSet.new,
            quoted_variables: []

  defmodule FuncInfo do
    @moduledoc false
    defstruct func_name: nil,
              arities: HashDict.new  # Map of arity to exported flag
  end

  defmodule TypeInfo do
    @moduledoc false
    defstruct arities: HashDict.new  # Map of arity to exported flag
  end

  defmodule MacroInfo do
    @moduledoc false
    defstruct const_name: nil,
              func_name: nil,
              define_tracker: nil,
              requires_init: nil
  end

  defmodule RecordInfo do
    @moduledoc false
    defstruct func_name: nil,
              fields: []
  end


  def build(erl_module, opts) do
    context = build(opts)
    context = Enum.reduce(erl_module.forms, context, &collect_func_info/2)
    context = Enum.reduce(context.funcs, context, &assign_strange_func_names/2)
    context = Enum.reduce(erl_module.exports, context, &collect_exports/2)
    context = Enum.reduce(erl_module.type_exports, context, &collect_type_exports/2)
    context = Enum.reduce(erl_module.forms, context, &collect_attr_info/2)
    context = Enum.reduce(erl_module.forms, context, &collect_record_info/2)
    context = Enum.reduce(erl_module.forms, context, &collect_macro_info/2)
    context
  end


  def build(_opts) do
    %Context{}
  end


  def set_quoted_variables(context, vars), do:
    %Context{context | quoted_variables: vars}


  def is_exported?(context, name, arity) do
    info = Dict.get(context.funcs, name, %FuncInfo{})
    Dict.get(info.arities, arity, false)
  end


  def is_type_exported?(context, name, arity) do
    info = Dict.get(context.types, name, %TypeInfo{})
    Dict.get(info.arities, arity, false)
  end


  def is_local_func?(context, name, arity) do
    info = Dict.get(context.funcs, name, %FuncInfo{})
    Dict.has_key?(info.arities, arity)
  end


  def is_quoted_var?(context, name) do
    Enum.member?(context.quoted_variables, name)
  end


  def local_function_name(context, name) do
    Dict.fetch!(context.funcs, name).func_name
  end


  def macro_function_name(context, name) do
    Dict.fetch!(context.macros, name).func_name |> ensure_exists
  end


  def record_function_name(context, name) do
    Dict.fetch!(context.records, name).func_name
  end


  def record_field_index(context, record_name, field_name) do
    (Dict.fetch!(context.records, record_name).fields
      |> Enum.find_index(fn f -> f == field_name end)) + 1
  end


  def record_field_names(context, record_name) do
    Dict.fetch!(context.records, record_name).fields
  end


  def needs_record_info?(context) do
    Dict.size(context.records) > 0 and not is_local_func?(context, :record_info, 2)
  end


  def map_records(context, func) do
    context.records |>
      Enum.map(fn {name, %RecordInfo{fields: fields}} ->
        func.(name, fields)
      end)
  end


  def macro_const_name(context, name) do
    Dict.fetch!(context.macros, name).const_name |> ensure_exists
  end


  def tracking_attr_name(context, name) do
    Dict.fetch!(context.macros, name).define_tracker
  end


  defp ensure_exists(x) when x != nil, do: x


  defp collect_func_info(%Erl2ex.ErlFunc{name: name, arity: arity}, context), do:
    add_func_info({name, arity}, context)
  defp collect_func_info(%Erl2ex.ErlImport{funcs: funcs}, context), do:
    Enum.reduce(funcs, context, &add_func_info/2)
  defp collect_func_info(_, context), do: context

  defp add_func_info({name, arity}, context) do
    if is_valid_elixir_func_name(name) do
      func_name = name
      used_func_names = HashSet.put(context.used_func_names, name)
    else
      func_name = nil
      used_func_names = context.used_func_names
    end
    func_info = Dict.get(context.funcs, name, %FuncInfo{func_name: func_name})
    func_info = %FuncInfo{func_info |
      arities: Dict.put(func_info.arities, arity, false)
    }
    %Context{context |
      funcs: Dict.put(context.funcs, name, func_info),
      used_func_names: used_func_names
    }
  end


  defp is_valid_elixir_func_name(name) do
    Regex.match?(~r/^[_a-z]\w*$/, Atom.to_string(name)) and
      not HashSet.member?(@elixir_reserved_words, name)
  end


  defp assign_strange_func_names({name, info = %FuncInfo{func_name: nil}}, context) do
    elixir_name = Regex.replace(~r/\W/, Atom.to_string(name), "_")
      |> find_available_name(context.used_func_names, "func")
    info = %FuncInfo{info | func_name: elixir_name}
    %Context{context |
      funcs: Dict.put(context.funcs, name, info),
      used_func_names: HashSet.put(context.used_func_names, elixir_name)
    }
  end
  defp assign_strange_func_names(_, context), do: context


  def collect_type_exports({name, arity}, context) do
    type_info = Dict.get(context.types, name, %TypeInfo{})
    type_info = %TypeInfo{type_info |
      arities: Dict.put(type_info.arities, arity, true)
    }
    %Context{context |
      types: Dict.put(context.types, name, type_info)
    }
  end


  def collect_exports({name, arity}, context) do
    func_info = Dict.fetch!(context.funcs, name)
    func_info = %FuncInfo{func_info |
      arities: Dict.put(func_info.arities, arity, true)
    }
    %Context{context |
      funcs: Dict.put(context.funcs, name, func_info)
    }
  end


  defp collect_attr_info(%Erl2ex.ErlAttr{name: name}, context) do
    %Context{context |
      used_attr_names: HashSet.put(context.used_attr_names, name)
    }
  end
  defp collect_attr_info(_, context), do: context


  defp collect_record_info(%Erl2ex.ErlRecord{name: name, fields: fields}, context) do
    macro_name = find_available_name(name, context.used_func_names, "erlrecord")
    record_info = %RecordInfo{
      func_name: macro_name,
      fields: fields |> Enum.map(&extract_record_field_name/1)
    }
    %Context{context |
      used_func_names: HashSet.put(context.used_func_names, macro_name),
      records: HashDict.put(context.records, name, record_info)
    }
  end
  defp collect_record_info(_, context), do: context


  defp collect_macro_info(%Erl2ex.ErlDefine{name: name, args: nil}, context) do
    macro = Dict.get(context.macros, name, %MacroInfo{})
    if macro.const_name == nil do
      macro_name = find_available_name(name, context.used_attr_names, "erlmacro")
      nmacro = %MacroInfo{macro |
        const_name: macro_name,
        requires_init: update_requires_init(macro.requires_init, false)
      }
      %Context{context |
        macros: Dict.put(context.macros, name, nmacro),
        used_attr_names: HashSet.put(context.used_attr_names, macro_name)
      }
    else
      context
    end
  end

  defp collect_macro_info(%Erl2ex.ErlDefine{name: name}, context) do
    macro = Dict.get(context.macros, name, %MacroInfo{})
    if macro.func_name == nil do
      macro_name = find_available_name(name, context.used_func_names, "erlmacro")
      nmacro = %MacroInfo{macro |
        func_name: macro_name,
        requires_init: update_requires_init(macro.requires_init, false)
      }
      %Context{context |
        macros: Dict.put(context.macros, name, nmacro),
        used_func_names: HashSet.put(context.used_func_names, macro_name)
      }
    else
      context
    end
  end

  defp collect_macro_info(%Erl2ex.ErlDirective{name: name}, context) when name != nil do
    macro = Dict.get(context.macros, name, %MacroInfo{})
    if macro.define_tracker == nil do
      tracker_name = find_available_name(name, context.used_attr_names, "defined")
      nmacro = %MacroInfo{macro |
        define_tracker: tracker_name,
        requires_init: update_requires_init(macro.requires_init, true)
      }
      %Context{context |
        macros: Dict.put(context.macros, name, nmacro),
        used_attr_names: HashSet.put(context.used_attr_names, tracker_name)
      }
    else
      context
    end
  end

  defp collect_macro_info(_, context), do: context


  defp extract_record_field_name({:record_field, _, {:atom, _, name}}), do: name
  defp extract_record_field_name({:record_field, _, {:atom, _, name}, _}), do: name


  defp update_requires_init(nil, nval), do: nval
  defp update_requires_init(oval, _nval), do: oval


  defp find_available_name(basename, used_names, prefix), do:
    find_available_name(to_string(basename), used_names, prefix, 1)

  defp find_available_name(basename, used_names, prefix, val) do
    suggestion = suggest_name(basename, prefix, val)
    if Set.member?(used_names, suggestion) do
      find_available_name(basename, used_names, prefix, val + 1)
    else
      suggestion
    end
  end

  defp suggest_name(basename, _, 0), do: basename
  defp suggest_name(basename, prefix, 1), do:
    String.to_atom("#{prefix}_#{basename}")
  defp suggest_name(basename, prefix, val), do:
    String.to_atom("#{prefix}#{val}_#{basename}")


end
