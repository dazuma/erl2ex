defmodule DummyTest do
  use ExUnit.Case

  @tag :skip
  test "dummy1" do
    IO.puts("")
    erl_source = """
      foo(A, B) ->
        receive
          A when B, C; D -> E;
          _ -> F
        end.
      """
    erl_ast = erl_source |> Erl2ex.ErlParse.from_str
    erl_ast |> inspect |> IO.puts
    ex_ast = erl_ast |> Erl2ex.Convert.module
    ex_ast |> inspect |> IO.puts
  end

end
