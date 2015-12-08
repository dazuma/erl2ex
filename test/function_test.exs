defmodule FunctionTest do
  use ExUnit.Case


  test "Single clause, single expr with no arguments or guards" do
    input = """
      foo() -> hello.
      """

    expected = """
      defp foo() do
        :hello
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Single clause, single expr with arguments but no guards" do
    input = """
      foo(A, B) -> A + B.
      """

    expected = """
      defp foo(a, b) do
        a + b
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Single clause, single expr with arguments and guards" do
    input = """
      foo(A, B) when A, is_atom(B); A + B > 0 -> hello.
      """

    expected = """
      defp foo(a, b) when a and is_atom(b) or a + b > 0 do
        :hello
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Multi clause, multi expr" do
    input = """
      foo(A) -> B = A + 1, B;
      foo({A}) -> B = A - 1, B.
      """

    expected = """
      defp foo(a) do
        b = a + 1
        b
      end

      defp foo({a}) do
        b = a - 1
        b
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


end
