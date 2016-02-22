
defmodule Erl2ex.Pipeline.Parse do

  @moduledoc false


  def string(str, opts \\ []) do
    charlist = generate_charlist(str)
    erl_forms = parse_erl_forms(charlist, opts)
    ext_forms = parse_ext_forms(charlist, opts)
    Enum.zip(erl_forms, ext_forms)
  end


  defp generate_charlist(str) do
    if not String.ends_with?(str, "\n") do
      str = str <> "\n"
    end
    String.to_char_list(str)
  end


  defp parse_erl_forms(charlist, opts) do
    charlist
      |> generate_token_group_stream
      |> Stream.map(&preprocess_tokens_for_erl/1)
      |> Stream.map(&(parse_erl_form(&1, opts)))
      |> Enum.to_list
  end


  defp generate_token_group_stream(charlist) do
    {charlist, 1}
      |> Stream.unfold(fn {ch, pos} ->
        case :erl_scan.tokens([], ch, pos, [:return_comments]) do
          {:done, {:ok, tokens, npos}, nch} -> {tokens, {nch, npos}}
          _ -> nil
        end
      end)
  end


  defp preprocess_tokens_for_erl(form_tokens), do:
    preprocess_tokens_for_erl(form_tokens, [])

  defp preprocess_tokens_for_erl([], result), do: Enum.reverse(result)
  defp preprocess_tokens_for_erl([{:"?", _}, {:"?", _}, {:atom, line, name} | tail], result), do:
    preprocess_tokens_for_erl(tail, [{:var, line, :"??#{name}"} | result])
  defp preprocess_tokens_for_erl([{:"?", _}, {:"?", _}, {:var, line, name} | tail], result), do:
    preprocess_tokens_for_erl(tail, [{:var, line, :"??#{name}"} | result])
  defp preprocess_tokens_for_erl([{:"?", _}, {:atom, line, name} | tail], result), do:
    preprocess_tokens_for_erl(tail, [{:var, line, :"?#{name}"} | result])
  defp preprocess_tokens_for_erl([{:"?", _}, {:var, line, name} | tail], result), do:
    preprocess_tokens_for_erl(tail, [{:var, line, :"?#{name}"} | result])
  defp preprocess_tokens_for_erl([{:comment, _, _} | tail], result), do:
    preprocess_tokens_for_erl(tail, result)
  defp preprocess_tokens_for_erl([tok | tail], result), do:
    preprocess_tokens_for_erl(tail, [tok | result])


  defp parse_erl_form([{:-, line} | defn_tokens = [{:atom, _, :define} | _]], opts) do
    parse_erl_define(line, defn_tokens, opts)
  end

  defp parse_erl_form([{:-, line} | defn_tokens = [{:atom, _, directive} | _]], opts)
  when directive == :ifdef or directive == :ifndef or directive == :undef do
    [{:call, _, {:atom, _, ^directive}, [value]}] =
      defn_tokens |> :erl_parse.parse_exprs |> handle_erl_parse_result(opts)
    {:attribute, line, directive, value}
  end

  defp parse_erl_form([{:-, line}, {:atom, _, directive}, {:dot, _}], _opts) do
    {:attribute, line, directive}
  end

  defp parse_erl_form(form_tokens, opts) do
    form_tokens |> :erl_parse.parse_form |> handle_erl_parse_result(opts)
  end


  defp parse_erl_define(line, [{:atom, _, :define}, {:"(", _}, name_token, {:",", dot_line} | replacement_tokens], opts) do
    parse_erl_define(line, [name_token, {:dot, dot_line}], replacement_tokens, opts)
  end

  defp parse_erl_define(line, [{:atom, _, :define}, {:"(", _} | remaining_tokens = [_, {:"(", _} | _]], opts) do
    close_paren_index = remaining_tokens
      |> Enum.find_index(fn
        {:")", _} -> true
        _ -> false
      end)
    {macro_tokens, [{:",", dot_line} | replacement_tokens]} = Enum.split(remaining_tokens, close_paren_index + 1)
    parse_erl_define(line, macro_tokens ++ [{:dot, dot_line}], replacement_tokens, opts)
  end


  defp parse_erl_define(line, macro_tokens, replacement_tokens, opts) do
    macro_expr = macro_tokens
      |> :erl_parse.parse_exprs
      |> handle_erl_parse_result(opts)
      |> hd
    replacement_tokens = replacement_tokens |> List.delete_at(-2)
    replacement_exprs = case :erl_parse.parse_exprs(replacement_tokens) do
      {:ok, asts} -> [asts]
      {:error, _} ->
        {guard_tokens, [{:dot, dot_line}]} = Enum.split(replacement_tokens, -1)
        temp_form_tokens = [{:atom, 1, :foo}, {:"(", 1}, {:")", 1}, {:when, 1}] ++
            guard_tokens ++
            [{:"->", dot_line}, {:atom, dot_line, :ok}, {:dot, dot_line}]
        {:ok, {:function, _, :foo, 0, [{:clause, _, [], guards, _}]}} = :erl_parse.parse_form(temp_form_tokens)
        guards
    end
    {:define, line, macro_expr, replacement_exprs}
  end


  defp handle_erl_parse_result({:ok, ast}, _opts), do: ast

  defp handle_erl_parse_result({:error, {line, :erl_parse, messages = [h | _]}}, opts) when is_list(h) do
    raise CompileError,
      file: Keyword.get(opts, :cur_file_path, "(unknown source file)"),
      line: line,
      description: Enum.join(messages)
  end

  defp handle_erl_parse_result({:error, {line, :erl_parse, messages}}, opts) do
    raise CompileError,
      file: Keyword.get(opts, :cur_file_path, "(unknown source file)"),
      line: line,
      description: inspect(messages)
  end

  defp handle_erl_parse_result(info, opts) do
    raise CompileError,
      file: Keyword.get(opts, :cur_file_path, "(unknown source file)"),
      line: :unknown,
      description: "Unknown error: #{inspect(info)}"
  end


  defp parse_ext_forms(charlist, opts) do
    comments = :erl_comment_scan.string(charlist)
    {:ok, io} = charlist
      |> preprocess_charlist_for_ext
      |> List.to_string
      |> StringIO.open
    case :epp_dodger.parse(io) do
      {:ok, forms} ->
        reconcile_comments(forms, comments)
      {:error, {line, _, desc}} ->
        raise CompileError,
          file: Keyword.get(opts, :cur_file_path, "(unknown source file)"),
          line: line,
          description: desc
    end
  end


  defp preprocess_charlist_for_ext(charlist) do
    {charlist, 1}
      |> Stream.unfold(fn {ch, pos} ->
        case :erl_scan.tokens([], ch, pos) do
          {:done, {:ok, tokens, npos}, nch} -> {tokens, {nch, npos}}
          _ -> nil
        end
      end)
      |> Enum.to_list
      |> List.flatten
      |> preprocess_tokens_for_ext([])
      |> unscan
  end


  defp preprocess_tokens_for_ext([], result), do: Enum.reverse(result)
  defp preprocess_tokens_for_ext([{:"?", _}, {:"?", _}, {type, line, name} | tail], result)
  when type == :atom or type == :var do
    preprocess_tokens_for_ext(tail, [{:atom, line, :"??#{name}"}, {:"?", line} | result])
  end
  defp preprocess_tokens_for_ext([tok | tail], result), do:
    preprocess_tokens_for_ext(tail, [tok | result])


  defp unscan(list) do
    list
      |> Enum.flat_map_reduce(1, fn tok, last_line ->
        line = elem(tok, 1)
        {generate_newlines(line - last_line) ++ unscan_token(tok), line}
      end)
      |> elem(0)
  end

  defp unscan_token({:atom, _, a}), do: :io_lib.write_atom(a) ++ ' '
  defp unscan_token({:string, _, s}), do: :io_lib.write_string(s) ++ ' '
  defp unscan_token({:char, _, c}), do: :io_lib.write_char(c) ++ ' '
  defp unscan_token({:float, _, f}), do: :erlang.float_to_list(f) ++ ' '
  defp unscan_token({:integer, _, n}), do: :erlang.integer_to_list(n) ++ ' '
  defp unscan_token({:var, _, a}), do: :erlang.atom_to_list(a) ++ ' '
  defp unscan_token({:dot, _}), do: '. '
  defp unscan_token({:., _}), do: '.'
  defp unscan_token({a, _}), do: :erlang.atom_to_list(a) ++ ' '

  defp generate_newlines(0), do: []
  defp generate_newlines(i), do: [?\n | generate_newlines(i - 1)]


  defp reconcile_comments(forms, _comments) do
    # TODO
    forms
  end

end
