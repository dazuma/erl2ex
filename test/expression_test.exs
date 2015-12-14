defmodule ExpressionTest do
  use ExUnit.Case


  test "Various value types" do
    input = """
      foo() -> atom, 123, $A, 3.14, {A, {}, {hello, world}}, [1, [], 2].
      """

    expected = """
      defp foo() do
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


  test "Math operations" do
    input = """
      foo() -> A + (B - C) / D * E,
        +A,
        -A,
        A div 1,
        A rem 1.
      """

    expected = """
      defp foo() do
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
      foo() ->
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
      defp foo() do
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
      foo() ->
        not A,
        A orelse B,
        A andalso B,
        A ++ B,
        A -- B,
        A ! B.
      """

    expected = """
      defp foo() do
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
      foo() ->
        A band B,
        A bor B,
        A bxor B,
        bnot A,
        A bsl 1,
        A bsr 1.
      """

    expected = """
      defp foo() do
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
      foo() ->
        case A of
          {B, 1} when B, C; D == 2 ->
            E = 3,
            E;
          _ -> 2
        end.
      """

    expected = """
      defp foo() do
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
      foo() ->
        if
          B, C; D == 2 ->
            E = 3,
            E;
          true -> 2
        end.
      """

    expected = """
      defp foo() do
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
      foo() ->
        receive
          A when B, C; D == 2 ->
            E = 3,
            E;
          _ -> 2
        end.
      """

    expected = """
      defp foo() do
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


  test "Simple fun" do
    input = """
      foo() ->
        fun
          (X) when B, C; D == 2 ->
            E = 3,
            E;
          (_) -> 2
        end.
      """

    expected = """
      defp foo() do
        fn
          x when b and c or d == 2 ->
            e = 3
            e
          _ ->
            2
        end
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Block" do
    input = """
      foo() ->
        begin
          E = 3,
          E
        end.
      """

    expected = """
      defp foo() do
        (
          e = 3
          e
        )
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


end
