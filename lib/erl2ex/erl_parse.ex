
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
    define = %Erl2ex.ErlDefine{
      line: line,
      name: name,
      args: args,
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

end
