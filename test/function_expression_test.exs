defmodule FunctionExpressionTest do
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


  test "Various value types" do
    input = """
      foo(A) -> atom, 123, $A, 3.14, {A, {}, {hello, world}}, [1, [], 2].
      """

    expected = """
      defp foo(a) do
        :atom
        123
        65
        3.14
        {a, {}, {:hello, :world}}
        [1, [], 2]
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Matches" do
    input = """
      foo() -> {A, [B]} = {1, [2]}.
      """

    expected = """
      defp foo() do
        {a, [b]} = {1, [2]}
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Function calls" do
    input = """
      foo(A) -> baz:bar(A, bar(A)).
      """

    expected = """
      defp foo(a) do
        :baz.bar(a, bar(a))
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Math operations" do
    input = """
      foo(A) -> A + (B - C) / D * E,
        +A,
        -A,
        A div 1,
        A rem 1.
      """

    expected = """
      defp foo(a) do
        a + (b - c) / d * e
        +a
        -a
        div(a, 1)
        rem(a, 1)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Comparison operations" do
    input = """
      foo(A) ->
        A == 1,
        A /= 1,
        A =< 1,
        A >= 1,
        A < 1,
        A > 1,
        A =:= 1,
        A =/= 1.
      """

    expected = """
      defp foo(a) do
        a == 1
        a != 1
        a <= 1
        a >= 1
        a < 1
        a > 1
        a === 1
        a !== 1
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Logic and misc operations" do
    input = """
      foo(A) ->
        not A,
        A orelse B,
        A andalso B,
        A ++ B,
        A -- B,
        A ! B.
      """

    expected = """
      defp foo(a) do
        not a
        a or b
        a and b
        a ++ b
        a -- b
        send(a, b)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Bitwise operations" do
    input = """
      foo(A) ->
        A band B,
        A bor B,
        A bxor B,
        bnot A,
        A bsl 1,
        A bsr 1.
      """

    expected = """
      defp foo(a) do
        a &&& b
        a ||| b
        a ^^^ b
        ~~~a
        a <<< 1
        a >>> 1
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Case statement" do
    input = """
      foo(A) ->
        case A of
          {B, 1} when B, C; D == 2 ->
            E = 3,
            E;
          _ -> 2
        end.
      """

    expected = """
      defp foo(a) do
        case(a) do
          {b, 1} when b and c or d == 2 ->
            e = 3
            e
          _ ->
            2
        end
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "If statement" do
    input = """
      foo(A) ->
        if
          B, C; D == 2 ->
            E = 3,
            E;
          true -> 2
        end.
      """

    expected = """
      defp foo(a) do
        cond() do
          b and c or d == 2 ->
            e = 3
            e
          true ->
            2
        end
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Receive statement" do
    input = """
      foo(A) ->
        receive
          A when B, C; D == 2 ->
            E = 3,
            E;
          _ -> 2
        end.
      """

    expected = """
      defp foo(a) do
        receive() do
          a when b and c or d == 2 ->
            e = 3
            e
          _ ->
            2
        end
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


end
