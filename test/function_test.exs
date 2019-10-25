defmodule FunctionTest do
  use ExUnit.Case

  import Erl2ex.TestHelper

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

  test "Local private function name is reserved or has strange characters" do
    input = """
    do() -> hello.
    'E=mc^2'() -> bye.
    foo() -> do(), 'E=mc^2'().
    """

    expected = """
    defp func_do() do
      :hello
    end


    defp func_E_mc_2() do
      :bye
    end


    defp foo() do
      func_do()
      func_E_mc_2()
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

  test "Local exported function name is reserved or has strange characters" do
    input = """
    -export([do/0, unquote/0, 'E=mc^2'/0, foo/0]).
    do() -> hello.
    unquote() -> world.
    'E=mc^2'() -> bye.
    foo() -> {do(), unquote(), 'E=mc^2'()}.
    """

    expected = """
    def unquote(:do)() do
      :hello
    end


    def unquote(:unquote)() do
      :world
    end


    def unquote(:"E=mc^2")() do
      :bye
    end


    def foo() do
      {__MODULE__.do(), Kernel.apply(__MODULE__, :unquote, []), Kernel.apply(__MODULE__, :"E=mc^2", [])}
    end
    """

    result = test_conversion(input, @opts)
    assert result.output == expected
    assert apply(result.module, :do, []) == :hello
    assert apply(result.module, :unquote, []) == :world
    assert apply(result.module, :"E=mc^2", []) == :bye
    assert apply(result.module, :foo, []) == {:hello, :world, :bye}
  end

  test "Call to remote functions whose name is reserved or has strange characters" do
    input = """
    foo() -> {blah:do(), blah:unquote(), blah:'E=mc^2'()}.
    """

    expected = """
    defp foo() do
      {:blah.do(), Kernel.apply(:blah, :unquote, []), Kernel.apply(:blah, :"E=mc^2", [])}
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

  test "Local private function name is a special form" do
    input = """
    'cond'(X) -> X.
    foo() -> 'cond'(a).
    """

    expected = """
    defp func_cond(x) do
      x
    end


    defp foo() do
      func_cond(:a)
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

  test "Local exported function name is a special form" do
    input = """
    -export(['cond'/1, foo/0]).
    'cond'(X) -> X.
    foo() -> 'cond'(a).
    """

    expected = """
    def cond(x) do
      x
    end


    def foo() do
      __MODULE__.cond(:a)
    end
    """

    result = test_conversion(input, @opts)
    assert result.output == expected
    assert apply(result.module, :foo, []) == :a
    assert apply(result.module, :cond, [:b]) == :b
  end

  test "Local private function name conflicts with auto-imported function" do
    input = """
    self() -> 1.
    foo() -> self().
    """

    expected = """
    defp func_self() do
      1
    end


    defp foo() do
      func_self()
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

  test "Local exported function name conflicts with auto-imported function" do
    input = """
    -export([self/0, foo/0]).
    self() -> 1.
    foo() -> self().
    """

    expected = """
    def self() do
      1
    end


    def foo() do
      __MODULE__.self()
    end
    """

    result = test_conversion(input, @opts)
    assert result.output == expected
    assert apply(result.module, :foo, []) == 1
    assert apply(result.module, :self, []) == 1
  end

  test "Imported function name is an elixir reserved word or special form" do
    input = """
    -import(mymod, [do/0, 'cond'/1]).
    foo() -> do(), 'cond'(x).
    """

    expected = """
    import :mymod, only: [do: 0, cond: 1]


    defp foo() do
      :mymod.do()
      :mymod.cond(:x)
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

  test "Imported function name has illegal characters" do
    input = """
    -import(mymod, ['minus-one'/1]).
    foo() -> 'minus-one'(x).
    """

    expected = """
    import :mymod, only: ["minus-one": 1]


    defp foo() do
      Kernel.apply(:mymod, :"minus-one", [:x])
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

  test "Variable name clash with a BIF name" do
    input = """
    foo() -> self().
    bar(Self) -> Self.
    """

    expected = """
    defp foo() do
      self()
    end


    defp bar(var_self) do
      var_self
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

  test "Local exported function named 'send'" do
    input = """
    -export([send/2]).
    send(X, Y) -> {X, Y}.
    foo(X, Y) -> X ! Y, send(X, Y).
    """

    expected = """
    def send(x, y) do
      {x, y}
    end


    defp foo(x, y) do
      Kernel.send(x, y)
      __MODULE__.send(x, y)
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

  test "Function pattern looks like keyword block" do
    input = """
    foo([{do, a}, {else, b}]) -> ok.
    """

    expected = """
    defp foo(do: :a, else: :b) do
      :ok
    end
    """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end
end
