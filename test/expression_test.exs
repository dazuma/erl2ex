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


  test "Variable case conversion" do
    input = """
      foo(_A, __B, _) -> 1.
      """

    expected = """
      defp foo(_a, __b, _) do
        1
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


  test "List destructuring" do
    input = """
      foo() -> [A, B | C] = X.
      """

    expected = """
      defp foo() do
        [a, b | c] = x
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


  test "Local fun reference" do
    input = """
      foo() -> fun sqrt/1.
      """

    expected = """
      defp foo() do
        &sqrt/1
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Remote fun reference" do
    input = """
      foo(A) -> fun A:sqrt/1.
      """

    expected = """
      defp foo(a) do
        &a.sqrt/1
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


  test "List comprehension" do
    input = """
      foo(X) -> [A + B || A <- [1,2,3], B <- X, A /= B].
      """

    expected = """
      defp foo(x) do
        for(a <- [1, 2, 3], b <- x, a != b) do
          a + b
        end
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Map literal" do
    input = """
      foo(X) -> \#{}, \#{a => X + 1, b => X - 1}.
      """

    expected = """
      defp foo(x) do
        %{}
        %{a: x + 1, b: x - 1}
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Map update with exact followed by inexact" do
    input = """
      foo() -> M\#{a := 1, b := 2, c => 3}.
      """

    expected = """
      defp foo() do
        Map.merge(%{m | a: 1, b: 2}, %{c: 3})
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Map update with inexact followed by exact" do
    input = """
      foo() -> M\#{a => 1, b => 2, c := 3}.
      """

    expected = """
      defp foo() do
        %{Map.merge(m, %{a: 1, b: 2}) | c: 3}
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Empty map update" do
    input = """
      foo() -> M\#{}.
      """

    expected = """
      defp foo() do
        m
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Map pattern match" do
    input = """
      foo(M) -> \#{a := X, b := {1, Y}} = M.
      """

    expected = """
      defp foo(m) do
        %{a: x, b: {1, y}} = m
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


end
