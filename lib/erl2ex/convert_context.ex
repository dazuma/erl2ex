
defmodule Erl2ex.Convert.Context do

  alias Erl2ex.Convert.Context


  defstruct exports: HashSet.new,
            macros: HashDict.new,
            local_funcs: HashSet.new,
            quoted_variables: []


  defmodule MacroInfo do
    defstruct has_const: false,
              func_name: nil,
              track_defines: false
  end


  def build(erl_module, opts) do
    exports = erl_module.exports |> Enum.into(HashSet.new)
    context = %Context{build(opts) | exports: exports}
    context = Enum.reduce(erl_module.forms, context, &collect_func_info/2)
    Enum.reduce(erl_module.forms, context, &collect_macro_info/2)
  end


  def build(_opts) do
    %Context{}
  end


  def is_exported?(context, name, arity) do
    Set.member?(context.exports, {name, arity})
  end


  def is_local_func?(context, name, arity) do
    Set.member?(context.local_funcs, {name, arity})
  end


  def is_quoted_var?(context, name) do
    Enum.member?(context.quoted_variables, name)
  end


  def macro_function_name(context, name) do
    Dict.fetch!(context.macros, name).func_name |> ensure_not_nil
  end


  defp ensure_not_nil(x) when x != nil, do: x


  defp collect_func_info(%Erl2ex.ErlFunc{name: name, arity: arity}, context), do:
    add_func_info({name, arity}, context)

  defp collect_func_info(%Erl2ex.ErlImport{funcs: funcs}, context) do
    funcs |> Enum.reduce(context, &add_func_info/2)
  end

  defp collect_func_info(_, context), do: context


  defp add_func_info(func_info = {name, _}, context) do
    %Context{context |
      local_funcs: [name, func_info] |> Enum.into(context.local_funcs)
    }
  end


  defp collect_macro_info(%Erl2ex.ErlDefine{name: name, args: args}, context) do
    macro = Dict.get(context.macros, name, %MacroInfo{})
    nmacro = cond do
      args == nil ->
        %MacroInfo{macro | has_const: true}
      macro.func_name == nil ->
        %MacroInfo{macro | func_name: decide_macro_func_name(name, context.local_funcs)}
      true ->
        macro
    end
    if args != nil and nmacro.func_name != nil do
      context = add_func_info({nmacro.func_name, Enum.count(args)}, context)
    end
    %Context{context | macros: Dict.put(context.macros, name, nmacro)}
  end
  # TODO: Look for ifdefs
  defp collect_macro_info(_, context), do: context


  defp decide_macro_func_name(basename, funcs, val \\ 1) do
    suggestion = suggest_macro_func_name(basename, val)
    if Set.member?(funcs, suggestion) do
      decide_macro_func_name(basename, funcs, val + 1)
    else
      suggestion
    end
  end


  defp suggest_macro_func_name(basename, 1), do: String.to_atom("epp_#{basename}")
  defp suggest_macro_func_name(basename, val), do: String.to_atom("epp#{val}_#{basename}")


end
