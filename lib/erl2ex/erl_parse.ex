
defmodule Erl2ex.ErlParse do

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
      |> Stream.map(&(parse_form(&1)))
      |> build_module(opts)
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


  defp parse_form(tokens) do
    {comment_tokens, form_tokens} = tokens
      |> Enum.partition(fn
        {:comment, _, _} -> true
        _ -> false
      end)
    {:ok, ast} = :erl_parse.parse_form(form_tokens)
    {ast, comment_tokens}
  end


  defp build_module(form_stream, _opts) do
    module = form_stream
      |> Enum.reduce(%Erl2ex.ErlModule{},
        fn ({ast, comments}, module) -> add_form(module, ast, comments) end)
    %Erl2ex.ErlModule{module | forms: Enum.reverse(module.forms)}
  end


  defp add_form(module, {:function, _line, name, arity, clauses}, comments) do
    func = %Erl2ex.ErlFunc{name: name, arity: arity, clauses: clauses, comments: comments}
    %Erl2ex.ErlModule{module | forms: [func | module.forms]}
  end

  defp add_form(module, {:attribute, _line, :module, arg}, comments) do
    %Erl2ex.ErlModule{module | name: arg, comments: module.comments ++ comments}
  end

  defp add_form(module, {:attribute, _line, :export, arg}, comments) do
    %Erl2ex.ErlModule{module |
      exports: module.exports ++ arg,
      comments: module.comments ++ comments
    }
  end

  defp add_form(module, {:attribute, line, attr, arg}, comments) do
    attribute = %Erl2ex.ErlAttr{line: line, name: attr, arg: arg, comments: comments}
    %Erl2ex.ErlModule{module | forms: [attribute | module.forms]}
  end

end
