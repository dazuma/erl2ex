defmodule PreprocessorTest do
  use ExUnit.Case


  test "Constant defines" do
    input = """
      -define(HELLO, 100 * 2).
      -define(hello, ?HELLO + 3).
      foo() -> ?HELLO.
      bar() -> ?hello.
      """

    expected = """
      @HELLO 100 * 2

      @hello @HELLO + 3


      defp foo() do
        @HELLO
      end


      defp bar() do
        @hello
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Simple macro define" do
    input = """
      -define(hello(X), 100 * X).
      foo() -> ?hello(2).
      """

    expected = """
      defmacrop hello(x) do
        quote do
          100 * unquote(x)
        end
      end


      defp foo() do
        hello(2)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


end
