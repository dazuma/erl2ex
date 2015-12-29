
defmodule Erl2ex.ErlParse do

  @moduledoc false

  alias Erl2ex.ErlAttr
  alias Erl2ex.ErlDefine
  alias Erl2ex.ErlDirective
  alias Erl2ex.ErlFunc
  alias Erl2ex.ErlImport
  alias Erl2ex.ErlModule
  alias Erl2ex.ErlRecord
  alias Erl2ex.ErlSpec
  alias Erl2ex.ErlType


  def from_file(path, opts \\ []) do
    path
      |> File.read!
      |> from_str([{:cur_file_path, path} | opts])
  end


  def from_io(io, opts \\ []) do
    io
      |> IO.read(:all)
      |> IO.chardata_to_string
      |> from_str(opts)
  end


  def from_str(str, opts \\ []) do
    context = build_context(opts)
    str
      |> to_char_list
      |> generate_token_group_stream
      |> Stream.map(&separate_comments/1)
      |> Stream.map(&preprocess_tokens/1)
      |> Stream.map(&(parse_form(context, &1)))
      |> build_module(context)
  end


  defmodule Context do
    @moduledoc false
    defstruct include_path: [],
              cur_file_path: nil,
              reverse_forms: false
  end


  defp build_context(opts) do
    include_path = opts
      |> Keyword.get_values(:include_dir)
      |> Enum.uniq
    %Context{
      include_path: include_path,
      cur_file_path: Keyword.get(opts, :cur_file_path, nil),
      reverse_forms: Keyword.get(opts, :reverse_forms, false)
    }
  end


  defp build_opts_for_include(context) do
    context.include_path
      |> Enum.map(&({:include_dir, &1}))
      |> Keyword.put(:reverse_forms, true)
  end


  defp find_file(context, path) do
    include_path = context.include_path
    if context.cur_file_path != nil do
      include_path = [Path.dirname(context.cur_file_path) | include_path]
    end
    include_path = [File.cwd!() | include_path]
    include_path
      |> Enum.find_value(fn dir ->
        full_path = Path.expand(path, dir)
        if File.regular?(full_path), do: full_path, else: false
      end)
  end


  defp cur_file_path_for_display(%Context{cur_file_path: nil}), do:
    "(Unknown source file)"

  defp cur_file_path_for_display(%Context{cur_file_path: path}), do:
    path


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


  defp parse_form(context, {[{:-, line} | defn_tokens = [{:atom, _, :define} | _]], comment_tokens}) do
    [{:call, _, {:atom, _, :define}, [macro, replacement]}] =
      defn_tokens |> :erl_parse.parse_exprs |> handle_parse_result(context)
    ast = {:define, line, macro, replacement}
    {ast, comment_tokens}
  end

  defp parse_form(_context, {[{:-, line}, {:atom, _, directive}, {:dot, _}], comment_tokens}) do
    ast = {:attribute, line, directive}
    {ast, comment_tokens}
  end

  defp parse_form(context, {form_tokens, comment_tokens}) do
    ast = form_tokens |> :erl_parse.parse_form |> handle_parse_result(context)
    {ast, comment_tokens}
  end


  defp handle_parse_result({:error, {line, :erl_parse, messages = [h | _]}}, context) when is_list(h), do:
    raise SyntaxError,
      file: cur_file_path_for_display(context),
      line: line,
      description: Enum.join(messages)

  defp handle_parse_result({:error, {line, :erl_parse, messages}}, context), do:
    raise SyntaxError,
      file: cur_file_path_for_display(context),
      line: line,
      description: inspect(messages)

  defp handle_parse_result({:ok, ast}, _context), do: ast

  defp handle_parse_result(info, context), do:
    raise SyntaxError,
      file: cur_file_path_for_display(context),
      line: :unknown,
      description: "Unknown error: #{inspect(info)}"


  defp build_module(form_stream, context) do
    module = form_stream
      |> Enum.reduce(%ErlModule{},
        fn ({ast, comments}, module) -> add_form(module, ast, comments, context) end)
    if not context.reverse_forms do
      module = %ErlModule{module | forms: Enum.reverse(module.forms)}
    end
    module
  end


  defp add_form(module, {:function, _line, name, arity, clauses}, comments, _context) do
    func = %ErlFunc{name: name, arity: arity, clauses: clauses, comments: comments}
    %ErlModule{module | forms: [func | module.forms]}
  end

  defp add_form(module, {:attribute, _line, :module, arg}, comments, _context) do
    %ErlModule{module |
      name: arg,
      comments: module.comments ++ comments
    }
  end

  defp add_form(module, {:attribute, _line, :include, path}, _comments, context) do
    file_path = find_file(context, path)
    opts = build_opts_for_include(context)
    included_module = from_file(file_path, opts)
    %ErlModule{module |
      forms: included_module.forms ++ module.forms
    }
  end

  defp add_form(module, {:attribute, _line, :export, arg}, comments, _context) do
    %ErlModule{module |
      exports: module.exports ++ arg,
      comments: module.comments ++ comments
    }
  end

  defp add_form(module, {:attribute, _line, :export_type, arg}, _comments, _context) do
    %ErlModule{module |
      type_exports: module.type_exports ++ arg
    }
  end

  defp add_form(module, {:attribute, line, :import, {modname, funcs}}, comments, _context) do
    attribute = %ErlImport{line: line, module: modname, funcs: funcs, comments: comments}
    %ErlModule{module |
      imports: module.imports ++ funcs,
      forms: [attribute | module.forms]
    }
  end

  defp add_form(module, {:attribute, line, :type, {name, defn, params}}, comments, _context) do
    type = %ErlType{line: line, kind: :type, name: name, params: params, defn: defn, comments: comments}
    %ErlModule{module | forms: [type | module.forms]}
  end

  defp add_form(module, {:attribute, line, :opaque, {name, defn, params}}, comments, _context) do
    type = %ErlType{line: line, kind: :opaque, name: name, params: params, defn: defn, comments: comments}
    %ErlModule{module | forms: [type | module.forms]}
  end

  defp add_form(module, {:attribute, line, :spec, {{name, _}, clauses}}, comments, _context) do
    spec = %ErlSpec{line: line, name: name, clauses: clauses, comments: comments}
    %ErlModule{module | specs: [spec | module.specs]}
  end

  defp add_form(module, {:attribute, line, :spec, {{spec_mod, name, _}, clauses}}, comments, _context) do
    if spec_mod == module.name do
      spec = %ErlSpec{line: line, name: name, clauses: clauses, comments: comments}
      %ErlModule{module | specs: [spec | module.specs]}
    else
      module
    end
  end

  defp add_form(module, {:attribute, line, :callback, {{name, _}, clauses}}, comments, _context) do
    callback = %ErlSpec{line: line, name: name, clauses: clauses, comments: comments}
    %ErlModule{module | forms: [callback | module.forms]}
  end

  defp add_form(module, {:attribute, line, :record, {recname, fields}}, comments, _context) do
    record = %ErlRecord{line: line, name: recname, fields: fields, comments: comments}
    %ErlModule{module | forms: [record | module.forms]}
  end

  defp add_form(module, {:attribute, line, directive}, comments, _context) do
    form = %ErlDirective{line: line, directive: directive, comments: comments}
    %ErlModule{module | forms: [form | module.forms]}
  end

  defp add_form(module, {:attribute, line, directive, name}, comments, _context)
      when directive == :ifdef or directive == :ifndef or directive == :undef do
    form = %ErlDirective{line: line, directive: directive, name: name, comments: comments}
    %ErlModule{module | forms: [form | module.forms]}
  end

  defp add_form(module, {:attribute, line, attr, arg}, comments, _context) do
    attribute = %ErlAttr{line: line, name: attr, arg: arg, comments: comments}
    %ErlModule{module | forms: [attribute | module.forms]}
  end

  defp add_form(module, {:define, line, macro, replacement}, comments, _context) do
    {name, args} = interpret_macro_expr(macro)
    define = %ErlDefine{
      line: line,
      name: name,
      args: args,
      replacement: replacement,
      comments: comments
    }
    %ErlModule{module | forms: [define | module.forms]}
  end

  defp add_form(_module, expr, _comments, context) do
    line = if is_tuple(expr) and tuple_size(expr) >= 3, do: elem(expr, 1), else: :unknown
    raise SyntaxError,
      file: cur_file_path_for_display(context),
      line: line,
      description: "Unrecognized Erlang form ast: #{inspect(expr)}"
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
