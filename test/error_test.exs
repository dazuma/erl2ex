defmodule ErrorTest do
  use ExUnit.Case

  @opts [emit_file_headers: false]


  test "Erlang parse error" do
    input = """
      foo() ->
        bar(.
      """

    expected = %CompileError{
      file: "(unknown source file)",
      line: 2,
      description: "syntax error before: '.'"
    }

    assert Erl2ex.convert_str(input, @opts) == {:error, expected}
  end


end
