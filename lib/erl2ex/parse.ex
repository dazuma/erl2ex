
defmodule Erl2ex.Parse do

  @moduledoc false


  alias Erl2ex.Parse.Context
  alias Erl2ex.Parse.ModuleBuilder


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
    context = Context.build(opts)
    str
      |> to_char_list
      |> generate_token_group_stream
      |> Stream.map(&separate_comments/1)
      |> Stream.map(&preprocess_tokens/1)
      |> Stream.map(&(parse_form(context, &1)))
      |> ModuleBuilder.build(context)
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


  defp parse_form(context, {[{:-, line} | defn_tokens = [{:atom, _, :define} | _]], comment_tokens}) do
    parse_define(context, line, defn_tokens, comment_tokens)
  end

  defp parse_form(context, {[{:-, line} | defn_tokens = [{:atom, _, directive} | _]], comment_tokens})
      when directive == :ifdef or directive == :ifndef or directive == :undef do
    [{:call, _, {:atom, _, ^directive}, [value]}] =
      defn_tokens |> :erl_parse.parse_exprs |> handle_parse_result(context)
    ast = {:attribute, line, directive, value}
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


  defp parse_define(context, line, [{:atom, _, :define}, {:"(", _}, name_token, {:",", dot_line} | replacement_tokens], comment_tokens) do
    parse_define(context, line, [name_token, {:dot, dot_line}], replacement_tokens, comment_tokens)
  end

  defp parse_define(context, line, [{:atom, _, :define}, {:"(", _} | remaining_tokens = [_, {:"(", _} | _]], comment_tokens) do
    close_paren_index = remaining_tokens
      |> Enum.find_index(fn
        {:")", _} -> true
        _ -> false
      end)
    {macro_tokens, [{:",", dot_line} | replacement_tokens]} = Enum.split(remaining_tokens, close_paren_index + 1)
    parse_define(context, line, macro_tokens ++ [{:dot, dot_line}], replacement_tokens, comment_tokens)
  end


  defp parse_define(context, line, macro_tokens, replacement_tokens, comment_tokens) do
    macro_expr = macro_tokens
      |> :erl_parse.parse_exprs
      |> handle_parse_result(context)
      |> hd
    replacement_exprs = replacement_tokens
      |> List.delete_at(-2)
      |> split_on_semicolon
      |> Enum.map(fn tokens ->
        tokens |> :erl_parse.parse_exprs |> handle_parse_result(context)
      end)
    ast = {:define, line, macro_expr, replacement_exprs}
    {ast, comment_tokens}
  end


  defp split_on_semicolon(list), do: split_on_semicolon(list, [[]])

  defp split_on_semicolon([], results), do:
    results |> Enum.map(&(Enum.reverse(&1))) |> Enum.reverse
  defp split_on_semicolon([{:";", line} | tlist], [hresults | tresults]), do:
    split_on_semicolon(tlist, [[], [{:dot, line} | hresults] | tresults])
  defp split_on_semicolon([hlist | tlist], [hresults | tresults]), do:
    split_on_semicolon(tlist, [[hlist | hresults] | tresults])


  defp handle_parse_result({:error, {line, :erl_parse, messages = [h | _]}}, context) when is_list(h), do:
    raise CompileError,
      file: Context.cur_file_path_for_display(context),
      line: line,
      description: Enum.join(messages)

  defp handle_parse_result({:error, {line, :erl_parse, messages}}, context), do:
    raise CompileError,
      file: Context.cur_file_path_for_display(context),
      line: line,
      description: inspect(messages)

  defp handle_parse_result({:ok, ast}, _context), do: ast

  defp handle_parse_result(info, context), do:
    raise CompileError,
      file: Context.cur_file_path_for_display(context),
      line: :unknown,
      description: "Unknown error: #{inspect(info)}"


end
