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


  test "Remote function calls" do
    input = """
      foo() -> baz:bar(A).
      """

    expected = """
      defp foo() do
        :baz.bar(a)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Anonymous function calls" do
    input = """
      foo(A, B) -> B(A).
      """

    expected = """
      defp foo(a, b) do
        b.(a)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Unqualified function calls" do
    input = """
      foo(A) -> bar(A).
      bar(A) -> statistics(A).
      baz(A) -> abs(A).
      """

    expected = """
      defp foo(a) do
        bar(a)
      end


      defp bar(a) do
        :erlang.statistics(a)
      end


      defp baz(a) do
        abs(a)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Imported function calls" do
    input = """
      -import(math, [pi/0, sin/1]).
      foo() -> pi().
      bar(A) -> cos(A).
      baz(A) -> sin(A).
      """

    expected = """
      import :math, only: [pi: 0, sin: 1]


      defp foo() do
        pi()
      end


      defp bar(a) do
        :erlang.cos(a)
      end


      defp baz(a) do
        sin(a)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "List of all auto-imported functions" do
    input = """
      foo() ->
        abs(A),
        bit_size(A),
        byte_size(A),
        is_atom(A),
        statistics(A).
      """

    expected = """
      defp foo() do
        abs(a)
        bit_size(a)
        byte_size(a)
        is_atom(a)
        :erlang.statistics(a)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Illegal use of elixir keywords as function names" do
    input = """
      do() -> hello.
      else() -> hello.
      'end'() -> hello.
      false() -> hello.
      fn() -> hello.
      nil() -> hello.
      true() -> hello.
      """

    expected = """
      defp func_do() do
        :hello
      end


      defp func_else() do
        :hello
      end


      defp func_end() do
        :hello
      end


      defp func_false() do
        :hello
      end


      defp func_fn() do
        :hello
      end


      defp func_nil() do
        :hello
      end


      defp func_true() do
        :hello
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Strange function names" do
    input = """
      'E=mc^2'() -> hello.
      """

    expected = """
      defp func_E_mc_2() do
        :hello
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


end
