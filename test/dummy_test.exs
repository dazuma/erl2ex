defmodule DummyTest do
  use ExUnit.Case

  @tag :skip
  test "dummy1" do
    IO.puts("")
    erl_source = """
      -import(hello, [foo/1, bar/2]).
      """

    erl_raw_tokens = {erl_source |> to_char_list, 1}
      |> Stream.unfold(fn {ch, pos} ->
        case :erl_scan.tokens([], ch, pos, [:return_comments]) do
          {:done, {:ok, tokens, npos}, nch} -> {tokens, {nch, npos}}
          _ -> nil
        end
      end)
      |> Enum.at(0)
    erl_raw_tokens |> inspect |> IO.puts

    erl_ast = erl_source |> Erl2ex.ErlParse.from_str
    erl_ast |> inspect |> IO.puts
    IO.puts("")
    ex_ast = erl_ast |> Erl2ex.Convert.module
    ex_ast |> inspect |> IO.puts
    IO.puts("")
    ex_source = ex_ast |> Erl2ex.ExWrite.to_str
    ex_source |> IO.puts
  end

end
