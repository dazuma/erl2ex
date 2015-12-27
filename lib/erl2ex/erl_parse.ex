
defmodule Erl2ex.ErlParse do

  @moduledoc false


  def from_file(path, opts \\ []) do
    path
      |> File.read!
      |> from_str([{:i, Path.dirname(path)} | opts])
  end


  def from_io(io, opts \\ []) do
    io
      |> IO.read(:all)
      |> IO.chardata_to_string
      |> from_str(opts)
  end


  def from_str(str, opts \\ []) do
    str
      |> to_char_list
      |> generate_token_group_stream
      |> Stream.map(&separate_comments/1)
      |> Stream.map(&preprocess_tokens/1)
      |> Stream.map(&parse_form/1)
      |> build_module(build_context(opts))
  end


  defmodule Context do
    @moduledoc false
    defstruct include_path: []
  end


  defp build_context(opts) do
    %Context{
      include_path: Keyword.get_values(opts, :i)
    }
  end


  defp generate_token_group_stream(str) do
    {str, 1}
      |> Stream.unfold(fn {ch, pos} ->
        case :erl_scan.tokens([], ch, pos, [:return_comments]) do
          {:done, {:ok, tokens, npos}, nch} -> {tokens, {nch, npos}}
          _ -> nil
        end
      end)
  end


  defp separate_comments(tokens) do
    tokens |> Enum.partition(fn
      {:comment, _, _} -> false
      _ -> true
    end)
  end


  defp preprocess_tokens({form_tokens, comment_tokens}) do
    {preprocess_tokens(form_tokens, []), comment_tokens}
  end


  defp preprocess_tokens([], result), do: Enum.reverse(result)
  defp preprocess_tokens([{:"?", _}, {:"?", _}, {:atom, line, name} | tail], result), do:
    preprocess_tokens(tail, [{:var, line, :"??#{name}"} | result])
  defp preprocess_tokens([{:"?", _}, {:"?", _}, {:var, line, name} | tail], result), do:
    preprocess_tokens(tail, [{:var, line, :"??#{name}"} | result])
  defp preprocess_tokens([{:"?", _}, {:atom, line, name} | tail], result), do:
    preprocess_tokens(tail, [{:var, line, :"?#{name}"} | result])
  defp preprocess_tokens([{:"?", _}, {:var, line, name} | tail], result), do:
    preprocess_tokens(tail, [{:var, line, :"?#{name}"} | result])
  defp preprocess_tokens([tok | tail], result), do:
    preprocess_tokens(tail, [tok | result])


  defp parse_form({[{:-, line} | defn_tokens = [{:atom, _, :define} | _]], comment_tokens}) do
    {:ok, [{:call, _, {:atom, _, :define}, [macro, replacement]}]} = :erl_parse.parse_exprs(defn_tokens)
    ast = {:define, line, macro, replacement}
    {ast, comment_tokens}
  end

  defp parse_form({[{:-, line}, {:atom, _, directive}, {:dot, _}], comment_tokens}) do
    ast = {:attribute, line, directive}
    {ast, comment_tokens}
  end

  defp parse_form({form_tokens, comment_tokens}) do
    {:ok, ast} = :erl_parse.parse_form(form_tokens)
    {ast, comment_tokens}
  end


  defp build_module(form_stream, context) do
    module = form_stream
      |> Enum.reduce(%Erl2ex.ErlModule{},
        fn ({ast, comments}, module) -> add_form(module, ast, comments, context) end)
    %Erl2ex.ErlModule{module | forms: Enum.reverse(module.forms)}
  end


  defp add_form(module, {:function, _line, name, arity, clauses}, comments, _context) do
    func = %Erl2ex.ErlFunc{name: name, arity: arity, clauses: clauses, comments: comments}
    %Erl2ex.ErlModule{module | forms: [func | module.forms]}
  end

  defp add_form(module, {:attribute, _line, :module, arg}, comments, _context) do
    %Erl2ex.ErlModule{module |
      name: arg,
      comments: module.comments ++ comments
    }
  end

  defp add_form(module, {:attribute, _line, :export, arg}, comments, _context) do
    %Erl2ex.ErlModule{module |
      exports: module.exports ++ arg,
      comments: module.comments ++ comments
    }
  end

  defp add_form(module, {:attribute, _line, :export_type, arg}, _comments, _context) do
    %Erl2ex.ErlModule{module |
      type_exports: module.type_exports ++ arg
    }
  end

  defp add_form(module, {:attribute, line, :import, {modname, funcs}}, comments, _context) do
    attribute = %Erl2ex.ErlImport{line: line, module: modname, funcs: funcs, comments: comments}
    %Erl2ex.ErlModule{module |
      imports: module.imports ++ funcs,
      forms: [attribute | module.forms]
    }
  end

  defp add_form(module, {:attribute, line, :type, {name, defn, params}}, comments, _context) do
    type = %Erl2ex.ErlType{line: line, kind: :type, name: name, params: params, defn: defn, comments: comments}
    %Erl2ex.ErlModule{module | forms: [type | module.forms]}
  end

  defp add_form(module, {:attribute, line, :opaque, {name, defn, params}}, comments, _context) do
    type = %Erl2ex.ErlType{line: line, kind: :opaque, name: name, params: params, defn: defn, comments: comments}
    %Erl2ex.ErlModule{module | forms: [type | module.forms]}
  end

  defp add_form(module, {:attribute, line, :spec, {{name, _}, clauses}}, comments, _context) do
    spec = %Erl2ex.ErlSpec{line: line, name: name, clauses: clauses, comments: comments}
    %Erl2ex.ErlModule{module | specs: [spec | module.specs]}
  end

  defp add_form(module, {:attribute, line, :callback, {{name, _}, clauses}}, comments, _context) do
    callback = %Erl2ex.ErlSpec{line: line, name: name, clauses: clauses, comments: comments}
    %Erl2ex.ErlModule{module | forms: [callback | module.forms]}
  end

  defp add_form(module, {:attribute, line, :record, {recname, fields}}, comments, _context) do
    record = %Erl2ex.ErlRecord{line: line, name: recname, fields: fields, comments: comments}
    %Erl2ex.ErlModule{module | forms: [record | module.forms]}
  end

  defp add_form(module, {:attribute, line, directive}, comments, _context) do
    form = %Erl2ex.ErlDirective{line: line, directive: directive, comments: comments}
    %Erl2ex.ErlModule{module | forms: [form | module.forms]}
  end

  defp add_form(module, {:attribute, line, directive, name}, comments, _context)
      when directive == :ifdef or directive == :ifndef or directive == :undef do
    form = %Erl2ex.ErlDirective{line: line, directive: directive, name: name, comments: comments}
    %Erl2ex.ErlModule{module | forms: [form | module.forms]}
  end

  defp add_form(module, {:attribute, line, attr, arg}, comments, _context) do
    attribute = %Erl2ex.ErlAttr{line: line, name: attr, arg: arg, comments: comments}
    %Erl2ex.ErlModule{module | forms: [attribute | module.forms]}
  end

  defp add_form(module, {:define, line, macro, replacement}, comments, _context) do
    {name, args} = interpret_macro_expr(macro)
    if args == nil do
      stringification_map = nil
    else
      {stringification_map, replacement} = resolve_stringifications(replacement)
    end
    define = %Erl2ex.ErlDefine{
      line: line,
      name: name,
      args: args,
      stringifications: stringification_map,
      replacement: replacement,
      comments: comments
    }
    %Erl2ex.ErlModule{module | forms: [define | module.forms]}
  end


  defp interpret_macro_expr({:call, _, name_expr, arg_exprs}) do
    name = macro_name(name_expr)
    args = arg_exprs |> Enum.map(fn {:var, _, n} -> n end)
    {name, args}
  end

  defp interpret_macro_expr(macro_expr) do
    name = macro_name(macro_expr)
    {name, nil}
  end


  defp macro_name({:var, _, name}), do: name
  defp macro_name({:atom, _, name}), do: name


  defp collect_variable_names({:var, _, var}, results), do:
    HashSet.put(results, var)

  defp collect_variable_names(tuple, results) when is_tuple(tuple), do:
    collect_variable_names(Tuple.to_list(tuple), results)

  defp collect_variable_names(list, results) when is_list(list), do:
    list |> Enum.reduce(results, &collect_variable_names/2)

  defp collect_variable_names(_, results), do: results


  defp find_available_name(basename, used_names, prefix, val) do
    suggestion = suggest_name(basename, prefix, val)
    if Set.member?(used_names, suggestion) do
      find_available_name(basename, used_names, prefix, val + 1)
    else
      suggestion
    end
  end

  defp suggest_name(basename, prefix, 1), do:
    String.to_atom("#{prefix}_#{basename}")
  defp suggest_name(basename, prefix, val), do:
    String.to_atom("#{prefix}#{val}_#{basename}")


  defp lower_str("_"), do: "_"
  defp lower_str(<< "_" :: utf8, rest :: binary >>), do:
    << "_" :: utf8, lower_str(rest) :: binary >>
  defp lower_str(<< first :: utf8, rest :: binary >>), do:
    << String.downcase(<< first >>) :: binary, rest :: binary >>


  defp map_stringification(stringified_arg, {stringification_map, all_vars}) do
    mapped_name = stringified_arg
      |> Atom.to_string
      |> String.lstrip(??)
      |> lower_str
      |> find_available_name(all_vars, "str", 1)
    updated_map = HashDict.put(stringification_map, stringified_arg, mapped_name)
    updated_vars_set = HashSet.put(all_vars, mapped_name)
    {updated_map, updated_vars_set}
  end


  defp modify_stringified_names({:var, line, var}, stringification_map), do:
    {:var, line, HashDict.get(stringification_map, var, var)}

  defp modify_stringified_names(tuple, stringification_map) when is_tuple(tuple), do:
    tuple
      |> Tuple.to_list
      |> Enum.map(&(modify_stringified_names(&1, stringification_map)))
      |> List.to_tuple

  defp modify_stringified_names(list, stringification_map) when is_list(list), do:
    list |> Enum.map(&(modify_stringified_names(&1, stringification_map)))

  defp modify_stringified_names(expr, _stringification_map), do: expr


  defp resolve_stringifications(replacement) do
    {stringified_args, normal_vars} = replacement
      |> collect_variable_names(HashSet.new)
      |> Enum.partition(fn var ->
        var
          |> Atom.to_string
          |> String.starts_with?("??")
      end)
    vars_set = normal_vars |> Enum.into(HashSet.new)
    {stringification_map, _all_vars} = stringified_args
      |> Enum.reduce({HashDict.new, vars_set}, &map_stringification/2)
    updated_replacement = modify_stringified_names(replacement, stringification_map)
    {stringification_map, updated_replacement}
  end


end
