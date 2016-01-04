defmodule ScopeTest do
  use ExUnit.Case

  @opts [emit_file_headers: false]


  test "Reference param var in toplevel function" do
    input = """
      foo(A) ->
        A = 3.
      """

    expected = """
      defp foo(a) do
        ^a = 3
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Reference previously matched var in toplevel function" do
    input = """
      foo(P, Q) ->
        [A] = P,
        {A} = Q.
      """

    expected = """
      defp foo(p, q) do
        [a] = p
        {^a} = q
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Reference var previously matched in a conditional" do
    input = """
      foo(P) ->
        if
          P -> A = 3
        end,
        A = 2.
      """

    expected = """
      defp foo(p) do
        cond() do
          p ->
            a = 3
        end
        ^a = 2
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Reference in a conditional a var previously matched outside" do
    input = """
      foo(P) ->
        A = 2,
        if
          P -> A = 3
        end.
      """

    expected = """
      defp foo(p) do
        a = 2
        cond() do
          p ->
            ^a = 3
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Inner fun match does not leak outside unless already declared" do
    input = """
      foo() ->
        fun () -> A = 1 end,
        A = 2,
        fun () -> A = 3 end.
      """

    expected = """
      defp foo() do
        fn -> a = 1 end
        a = 2
        fn -> ^a = 3 end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Inner fun param shadows external variable of the same name" do
    input = """
      foo(A) -> fun (A) -> ok end.
      """

    expected = """
      defp foo(a) do
        fn a -> :ok end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Matches in case statement reference already declared variables" do
    input = """
      foo(A) ->
        case 1 of
          A -> ok;
          B -> B
        end.
      """

    expected = """
      defp foo(a) do
        case(1) do
          ^a ->
            :ok
          b ->
            b
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Variable occurs multiple times within a match" do
    input = """
      foo(A, A) ->
        A = 2,
        {B, B, C = {B}} = A,
        fun(C, {C}, D = C) -> ok end,
        B = 3.
      """

    expected = """
      defp foo(a, a) do
        ^a = 2
        {b, b, c = {b}} = a
        fn c, {c}, d = c -> :ok end
        ^b = 3
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Underscore should never have a caret" do
    input = """
      foo(_, _) ->
        _ = 3,
        case 1 of
          _ -> ok
        end.
      """

    expected = """
      defp foo(_, _) do
        _ = 3
        case(1) do
          _ ->
            :ok
        end
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


end
