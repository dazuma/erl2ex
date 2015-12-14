defmodule PreprocessorTest do
  use ExUnit.Case


  test "Constant defines with a nested define" do
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


  test "Simple function defines with a nested define" do
    input = """
      -define(hello(X), 100 * X).
      -define(HELLO(X), ?hello(X) + 2).
      foo() ->
        ?hello(2),
        ?HELLO(3).
      """

    expected = """
      defmacrop epp_hello(x) do
        quote do
          100 * unquote(x)
        end
      end


      defmacrop epp_HELLO(x) do
        quote do
          epp_hello(unquote(x)) + 2
        end
      end


      defp foo() do
        epp_hello(2)
        epp_HELLO(3)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Function defines with name collisions" do
    input = """
      -define(Foo(X), X + 1).
      -define(foo(X), ?Foo(X) + 2).
      epp_foo() ->
        ?foo(0).
      """

    expected = """
      defmacrop epp_Foo(x) do
        quote do
          unquote(x) + 1
        end
      end


      defmacrop epp2_foo(x) do
        quote do
          epp_Foo(unquote(x)) + 2
        end
      end


      defp epp_foo() do
        epp2_foo(0)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


end
