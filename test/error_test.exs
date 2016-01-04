defmodule ErrorTest do
  use ExUnit.Case

  @opts [emit_file_headers: false]


  test "Erlang parse error" do
    input = """
      foo() ->
        bar(.
      """

    expected = {"(Unknown source file)", 2, "syntax error before: '.'"}

    assert Erl2ex.convert_str(input, @opts) == {:error, expected}
  end


end
