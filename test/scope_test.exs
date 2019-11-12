defmodule ScopeTest do
  use ExUnit.Case

  @opts [emit_file_headers: false]

  test "Illegal variable names" do
    input = """
    foo() ->
      Do = 1,
      Else = 2,
      End = 3,
      False = 4,
      Fn = 5,
      Nil = 6,
      True = 7.
    """

    expected = """
    defp foo() do
      var_do = 1
      var_else = 2
      var_end = 3
      var_false = 4
      var_fn = 5
      var_nil = 6
      var_true = 7
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

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

  test "Reference vars previously matched in a conditional" do
    input = """
    foo(P) ->
      case P of
        1 -> A = 1, B = 1;
        B -> A = 2
      end,
      A = 0,
      B = 0.
    """

    expected = """
    defp foo(p) do
      case(p) do
        1 ->
          a = 1
          b = 1
        b ->
          a = 2
      end
      ^a = 0
      ^b = 0
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

  test "Reference in a conditional a var previously matched outside" do
    input = """
    foo(P) ->
      A = 2,
      case P of
        1 -> A = 3
      end.
    """

    expected = """
    defp foo(p) do
      a = 2
      case(p) do
        1 ->
          ^a = 3
      end
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

  test "Inner fun match does not export unless already declared in the surrounding scope" do
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

  test "List comprehension param shadows external variable of the same name" do
    input = """
    foo() ->
      [X || X <- [2,3]],
      X = 1,
      [X || X <- [2,3]].
    """

    expected = """
    defp foo() do
      for(x <- [2, 3], into: [], do: x)
      x = 1
      for(x <- [2, 3], into: [], do: x)
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

  test "String comprehension param shadows external variable of the same name" do
    input = """
    foo() ->
      << <<X>> || <<X>> <= <<2,3>> >>,
      X = 1,
      << <<X>> || <<X>> <= <<2,3>> >>.
    """

    expected = """
    defp foo() do
      for(<<(x <- <<2, 3>>)>>, into: <<>>, do: <<x>>)
      x = 1
      for(<<(x <- <<2, 3>>)>>, into: <<>>, do: <<x>>)
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

  test "Case statement clauses do not clash, but variables are exported" do
    input = """
    foo(P) ->
      case P of
        A -> 1;
        {A} -> 2
      end,
      A = 3.
    """

    expected = """
    defp foo(p) do
      case(p) do
        a ->
          1
        {a} ->
          2
      end
      ^a = 3
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

  test "Variables can occur multiple times within a match" do
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
