
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
      file: Context.cur_file_path_for_display(context),
      line: line,
      description: Enum.join(messages)

  defp handle_parse_result({:error, {line, :erl_parse, messages}}, context), do:
    raise SyntaxError,
      file: Context.cur_file_path_for_display(context),
      line: line,
      description: inspect(messages)

  defp handle_parse_result({:ok, ast}, _context), do: ast

  defp handle_parse_result(info, context), do:
    raise SyntaxError,
      file: Context.cur_file_path_for_display(context),
      line: :unknown,
      description: "Unknown error: #{inspect(info)}"


end
