defmodule ErrorTest do
  use ExUnit.Case


  test "Erlang parse error" do
    input = """
      foo() ->
        bar(.
      """

    expected = {"(Unknown source file)", 2, "syntax error before: '.'"}

    assert Erl2ex.convert_str(input) == {:error, expected}
  end


end
