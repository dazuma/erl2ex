defmodule PreprocessorTest do
  use ExUnit.Case


  test "Macro constant defines with a nested define" do
    input = """
      -define(HELLO, 100 * 2).
      -define(hello, ?HELLO + 3).
      foo() -> ?HELLO.
      bar() -> ?hello.
      """

    expected = """
      @erlmacro_HELLO 100 * 2

      @erlmacro_hello @erlmacro_HELLO + 3


      defp foo() do
        @erlmacro_HELLO
      end


      defp bar() do
        @erlmacro_hello
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Simple macro function defines with a nested define" do
    input = """
      -define(hello(X), 100 * X).
      -define(HELLO(X), ?hello(X) + 2).
      foo() ->
        ?hello(2),
        ?HELLO(3).
      """

    expected = """
      defmacrop erlmacro_hello(x) do
        quote do
          100 * unquote(x)
        end
      end


      defmacrop erlmacro_HELLO(x) do
        quote do
          erlmacro_hello(unquote(x)) + 2
        end
      end


      defp foo() do
        erlmacro_hello(2)
        erlmacro_HELLO(3)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Macro function collides with function name" do
    input = """
      -define(Foo(X), X + 1).
      -define(foo(X), ?Foo(X) + 2).
      erlmacro_foo() ->
        ?foo(0).
      """

    expected = """
      defmacrop erlmacro_Foo(x) do
        quote do
          unquote(x) + 1
        end
      end


      defmacrop erlmacro2_foo(x) do
        quote do
          erlmacro_Foo(unquote(x)) + 2
        end
      end


      defp erlmacro_foo() do
        erlmacro2_foo(0)
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Basic directives" do
    input = """
      -define(debug, 1).
      -ifdef(debug).
      foo() -> 1.
      -else.
      -ifndef(debug).
      foo() -> 2.
      -endif.
      -endif.
      -undef(debug).
      """

    expected = """
      @erlmacro_debug 1
      @defined_debug true

      if @defined_debug do


      defp foo() do
        1
      end


      else

      if not @defined_debug do


      defp foo() do
        2
      end


      end

      end

      @defined_debug false
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Macro name collides with attribute name" do
    input = """
      -erlmacro_vsn(1).
      -define(vsn, 2).
      -ifdef(vsn).
      -endif.
      """

    expected = """
      Module.register_attribute(__MODULE__, :erlmacro_vsn, persist: true, accumulate: true)
      @erlmacro_vsn 1

      @erlmacro2_vsn 2
      @defined_vsn true

      if @defined_vsn do

      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Macro define tester name collides with attribute name" do
    input = """
      -defined_vsn(1).
      -define(vsn, 2).
      -ifdef(vsn).
      -endif.
      """

    expected = """
      Module.register_attribute(__MODULE__, :defined_vsn, persist: true, accumulate: true)
      @defined_vsn 1

      @erlmacro_vsn 2
      @defined2_vsn true

      if @defined2_vsn do

      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


  test "Predefined macros" do
    input = """
      foo() ->
        ?MODULE,
        ?MODULE_STRING,
        ?FILE,
        ?LINE,
        ?MACHINE.
      """

    expected = """
      defp foo() do
        __MODULE__
        Atom.to_char_list(__MODULE__)
        String.to_char_list(__ENV__.file())
        __ENV__.line()
        'BEAM'
      end
      """

    assert Erl2ex.convert_str(input) == expected
  end


end
