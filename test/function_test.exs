defmodule FunctionTest do
  use ExUnit.Case

  @opts [emit_file_headers: false]


  test "Single clause, single expr with no arguments or guards" do
    input = """
      foo() -> hello.
      """

    expected = """
      defp foo() do
        :hello
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Remote function calls with an expression as the function name" do
    input = """
      foo(A, B) -> baz:A(B).
      """

    expected = """
      defp foo(a, b) do
        :erlang.apply(:baz, a, [b])
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Remote function calls with an expression as the module name" do
    input = """
      foo(A, B) -> A:baz(B).
      """

    expected = """
      defp foo(a, b) do
        a.baz(b)
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Strange function names" do
    input = """
      'E=mc^2'() -> hello.
      foo() -> 'E=mc^2'().
      """

    expected = """
      defp func_E_mc_2() do
        :hello
      end


      defp foo() do
        func_E_mc_2()
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Variable and function name clash" do
    input = """
      foo() -> 1.
      bar(Foo) -> foo() + Foo.
      """

    expected = """
      defp foo() do
        1
      end


      defp bar(var_foo) do
        foo() + var_foo
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Variable and function name clash beginning with underscore" do
    input = """
      '_foo'() -> 1.
      bar(_Foo) -> '_foo'().
      """

    expected = """
      defp _foo() do
        1
      end


      defp bar(_var_foo) do
        _foo()
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Simple specs" do
    input = """
      -spec foo(A :: atom(), integer()) -> boolean()
        ; (A :: integer(), B :: atom()) -> 'hello' | boolean().
      foo(A, B) -> true.
      """

    expected = """
      @spec foo(atom(), integer()) :: boolean()
      @spec foo(integer(), atom()) :: :hello | boolean()

      defp foo(a, b) do
        true
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Specs with variables" do
    input = """
      -spec foo(A, B) -> A | B.
      foo(A, B) -> A.
      """

    expected = """
      @spec foo(a, b) :: a | b

      defp foo(a, b) do
        a
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Specs with guards" do
    input = """
      -spec foo(A, B) -> A | B when A :: tuple(), B :: atom().
      foo(A, B) -> A.
      """

    expected = """
      @spec foo(a, b) :: a | b when a: tuple(), b: atom()

      defp foo(a, b) do
        a
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Specs with module qualifiers" do
    input = """
      -module(mod).
      -spec mod:foo(atom()) -> boolean().
      -spec mod2:foo(integer()) -> boolean().
      foo(A) -> true.
      """

    expected = """
      defmodule :mod do

        @spec foo(atom()) :: boolean()

        defp foo(a) do
          true
        end

      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


end
