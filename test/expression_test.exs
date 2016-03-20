defmodule ExpressionTest do
  use ExUnit.Case

  import Erl2ex.TestHelper


  @opts [emit_file_headers: false]


  test "Various value types" do
    input = """
      -export([foo/1]).
      foo(A) -> [atom, 123, 3.14, {A, {}, {hello, "world"}}, [1, [], 2]].
      """

    expected = """
      def foo(a) do
        [:atom, 123, 3.14, {a, {}, {:hello, 'world'}}, [1, [], 2]]
      end
      """

    result = test_conversion(input, @opts)
    assert result.output == expected
    assert apply(result.module, :foo, [:x]) == [:atom, 123, 3.14, {:x, {}, {:hello, 'world'}}, [1, [], 2]]
  end


  test "Character values" do
    input = """
      -export([foo/0]).
      foo() -> $A + $🐱 + $\\n + $".
      """

    expected = """
      def foo() do
        ?A + ?🐱 + ?\\n + ?"
      end
      """

    result = test_conversion(input, @opts)
    assert result.output == expected
    assert apply(result.module, :foo, []) == 128158
  end


  test "String escaping" do
    input = """
      foo() ->
        "hi\#{1}",
        "\\n\\s".
      """

    expected = """
      defp foo() do
        'hi\\\#{1}'
        '\\n '
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Logic and misc operations" do
    input = """
      foo() ->
        not A,
        A orelse B,
        A andalso B,
        A and B,
        A or B,
        A xor B,
        A ++ B,
        A -- B,
        A ! B.
      """

    expected = """
      defp foo() do
        not a
        a or b
        a and b
        :erlang.and(a, b)
        :erlang.or(a, b)
        :erlang.xor(a, b)
        a ++ b
        a -- b
        send(a, b)
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
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
      use Bitwise, only_operators: true


      defp foo() do
        a &&& b
        a ||| b
        a ^^^ b
        ~~~a
        a <<< 1
        a >>> 1
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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
        case(:if) do
          :if when b and c or d == 2 ->
            e = 3
            e
          :if when true ->
            2
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "If statement that generates errors" do
    input = """
      foo() ->
        if
          hd([]) -> 1;
          true -> 2
        end.
      """

    expected = """
      defp foo() do
        case(:if) do
          :if when hd([]) ->
            1
          :if when true ->
            2
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Receive with timeout" do
    input = """
      foo() ->
        receive
          A -> ok
        after
          100 -> err
        end.
      """

    expected = """
      defp foo() do
        receive() do
          a ->
            :ok
        after
          100 ->
            :err
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "List comprehension" do
    input = """
      foo(X) -> [A + B || A <- [1,2,3], B <- X, A /= B].
      """

    expected = """
      defp foo(x) do
        for(a <- [1, 2, 3], b <- x, a != b, into: [], do: a + b)
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "List comprehension with binary generator" do
    input = """
      foo() -> [A + B || <<A, B>> <= <<1, 2, 3, 4>>].
      """

    expected = """
      defp foo() do
        for(<<a, (b <- <<1, 2, 3, 4>>)>>, into: [], do: a + b)
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "List comprehension with no generator" do
    input = """
      foo(X) -> [x || X].
      """

    expected = """
      defp foo(x) do
        if(x) do
          for(into: [], do: :x)
        else
          []
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "List comprehension starting with static qualifiers" do
    input = """
      foo(X, Y, Z) -> [A || X, Y, Z, A <- [1,2], A > 1].
      """

    expected = """
      defp foo(x, y, z) do
        if(x and y and z) do
          for(a <- [1, 2], a > 1, into: [], do: a)
        else
          []
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Binary comprehension with binary generator" do
    input = """
      foo() -> << <<B, A>> || <<A, B>> <= <<1, 2, 3, 4>> >>.
      """

    expected = """
      defp foo() do
        for(<<a, (b <- <<1, 2, 3, 4>>)>>, into: <<>>, do: <<b, a>>)
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Binary comprehension with no generator" do
    input = """
      foo(X) -> << <<1>> || X>>.
      """

    expected = """
      defp foo(x) do
        if(x) do
          for(into: <<>>, do: <<1>>)
        else
          <<>>
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Binary comprehension starting with static qualifiers" do
    input = """
      foo(X, Y, Z) -> << <<A>> || X, Y, Z, <<A>> <= <<1,2>>, A > 1>>.
      """

    expected = """
      defp foo(x, y, z) do
        if(x and y and z) do
          for(<<(a <- <<1, 2>>)>>, a > 1, into: <<>>, do: <<a>>)
        else
          <<>>
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Bitstring literal with no qualifiers" do
    input = """
      foo() -> <<1, 2, "hello">>.
      """

    expected = """
      defp foo() do
        <<1, 2, "hello">>
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Bitstring literal with size expressions" do
    input = """
      foo(A, B) -> <<1:10, 2:A>> = B.
      """

    expected = """
      defp foo(a, b) do
        <<1::10, 2::size(a)>> = b
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Bitstring literal with size expressions and explicit binary type" do
    input = """
      -export([foo/1]).
      foo(A) ->
        <<B:2/binary, C:A/binary, D/binary>> = <<1, 2, 3, 4, 5>>,
        {B, C, D}.
      """

    expected = """
      def foo(a) do
        <<b::size(2)-binary, c::size(a)-binary, d::binary>> = <<1, 2, 3, 4, 5>>
        {b, c, d}
      end
      """

    result = test_conversion(input, @opts)
    assert result.output == expected
    assert apply(result.module, :foo, [2]) == {<<1, 2>>, <<3, 4>>, <<5>>}

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Bitstring literal with simple type specifiers" do
    input = """
      foo() -> <<1/integer, 2/float, "hello"/utf16>>.
      """

    expected = """
      defp foo() do
        <<1::integer, 2::float, "hello"::utf16>>
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Bitstring literal with complex type specifiers" do
    input = """
      foo() -> <<1:4/integer-signed-unit:4-native>>.
      """

    expected = """
      defp foo() do
        <<1::size(4)-integer-signed-unit(4)-native>>
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  @tag :skip  # Not yet supported
  test "Bitstring literal with complex types" do
    input = """
      foo() -> <<1:16/integer-signed-native>>.
      """

    expected = """
      defp foo() do
        ???
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Bitstring pattern match" do
    input = """
      foo(S) -> <<A, B:10, C:D, E/float, F/binary>> = S.
      """

    expected = """
      defp foo(s) do
        <<a, b::10, c::size(d), e::float, f::binary>> = s
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Try with all features" do
    input = """
      foo() ->
        try
          X, Y
        of
          A -> A + 2
        catch
          throw:B when is_integer(B) -> B;
          C -> C;
          exit:D when D == 0 -> D;
          error:badarith -> E;
          Kind:H -> {Kind, H}
        after
          F, G
        end.
      """

    expected = """
      defp foo() do
        try() do
          x
          y
        catch
          (:throw, b) when is_integer(b) ->
            b
          :throw, c ->
            c
          (:exit, d) when d == 0 ->
            d
          :error, :badarith ->
            e
          kind, h ->
            {kind, h}
        after
          f
          g
        else
          a ->
            a + 2
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Catch expression" do
    input = """
      foo() ->
        catch A.
      """

    expected = """
      defp foo() do
        try() do
          a
        catch
          :throw, term ->
            term
          :exit, reason ->
            {:EXIT, reason}
          :error, reason ->
            {:EXIT, {reason, :erlang.get_stacktrace()}}
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

end
