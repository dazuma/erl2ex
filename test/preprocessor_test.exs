defmodule PreprocessorTest do
  use ExUnit.Case

  @opts [emit_file_headers: false]


  test "Macro constant defines with a nested define" do
    input = """
      -define(HELLO, 100 * 2).
      -define(hello, ?HELLO + 3).
      foo() -> ?HELLO.
      bar() -> ?hello.
      """

    expected = """
      defmacrop erlconst_HELLO() do
        quote do
          100 * 2
        end
      end


      defmacrop erlconst_hello() do
        quote do
          erlconst_HELLO() + 3
        end
      end


      defp foo() do
        erlconst_HELLO()
      end


      defp bar() do
        erlconst_hello()
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Macro that includes semicolons and should work only for guards" do
    input = """
      -define(HELLO(X), X > 10, X < 20; X == 1).
      foo(X) when ?HELLO(X) -> X.
      """

    expected = """
      defmacrop erlmacro_HELLO(x) do
        quote do
          unquote(x) > 10 and unquote(x) < 20 or unquote(x) == 1
        end
      end


      defp foo(x) when erlmacro_HELLO(x) do
        x
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Macro that includes commas and works differently in guards" do
    input = """
      -define(HELLO(X), X > 10, X < 20).
      foo(X) when ?HELLO(X) -> ?HELLO(X).
      """

    expected = """
      defmacrop erlmacro_HELLO(x) do
        if Macro.Env.in_guard? do
          quote do
            unquote(x) > 10 and unquote(x) < 20
          end
        else
          quote do
            (
              unquote(x) > 10
              unquote(x) < 20
            )
          end
        end
      end


      defp foo(x) when erlmacro_HELLO(x) do
        erlmacro_HELLO(x)
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Macro constant and function defines with the same name" do
    input = """
      -define(HELLO, 100 * 2).
      -define(HELLO(), ?HELLO + 1).
      -define(HELLO(X), ?HELLO() + X).
      foo() -> ?HELLO.
      bar() -> ?HELLO().
      baz() -> ?HELLO(2).
      """

    expected = """
      defmacrop erlconst_HELLO() do
        quote do
          100 * 2
        end
      end


      defmacrop erlmacro_HELLO() do
        quote do
          erlconst_HELLO() + 1
        end
      end


      defmacrop erlmacro_HELLO(x) do
        quote do
          erlmacro_HELLO() + unquote(x)
        end
      end


      defp foo() do
        erlconst_HELLO()
      end


      defp bar() do
        erlmacro_HELLO()
      end


      defp baz() do
        erlmacro_HELLO(2)
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Macro function with arg stringification" do
    input = """
      -define(hello(X), ??X).
      foo() ->
        ?hello(2 + 3).
      """

    expected = """
      defmacrop erlmacro_hello(x) do
        str_x = Macro.to_string(quote do: unquote(x))
        quote do
          unquote(str_x)
        end
      end


      defp foo() do
        erlmacro_hello(2 + 3)
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Arg stringification name collides with function name" do
    input = """
      -define(hello(X), ??X ++ str_x()).
      str_x() -> "hi".
      """

    expected = """
      defmacrop erlmacro_hello(x) do
        str2_x = Macro.to_string(quote do: unquote(x))
        quote do
          unquote(str2_x) ++ str_x()
        end
      end


      defp str_x() do
        'hi'
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
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
      defmacrop erlconst_debug() do
        quote do
          1
        end
      end
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

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Basic directives with capitalized names" do
    input = """
      -define(DEBUG, 1).
      -ifdef(DEBUG).
      foo() -> 1.
      -else.
      -ifndef(DEBUG).
      foo() -> 2.
      -endif.
      -endif.
      -undef(DEBUG).
      """

    expected = """
      defmacrop erlconst_DEBUG() do
        quote do
          1
        end
      end
      @defined_DEBUG true


      if @defined_DEBUG do


      defp foo() do
        1
      end


      else


      if not @defined_DEBUG do


      defp foo() do
        2
      end


      end


      end


      @defined_DEBUG false
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
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


      defmacrop erlconst_vsn() do
        quote do
          2
        end
      end
      @defined2_vsn true


      if @defined2_vsn do


      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Macro tested before defined" do
    input = """
      -ifdef(TEST).
      -endif.
      """

    expected = """
      @defined_TEST System.get_env("DEFINE_TEST") != nil


      if @defined_TEST do


      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Macro tested before defined, with custom prefix" do
    input = """
      -ifdef(TEST).
      -endif.
      """

    expected = """
      @defined_TEST System.get_env("ERL_DEFINE_TEST") != nil


      if @defined_TEST do


      end
      """

    assert Erl2ex.convert_str!(input, Keyword.merge(@opts, [define_prefix: "ERL_DEFINE_"])) == expected
  end


  test "Macro tested before defined, using config" do
    input = """
      -ifdef(TEST).
      -endif.
      """

    expected = """
      @defined_TEST Application.get_env(:erl2ex, :ERL_DEFINE_TEST) != nil


      if @defined_TEST do


      end
      """

    assert Erl2ex.convert_str!(input, Keyword.merge(@opts, [defines_from_config: "erl2ex", define_prefix: "ERL_DEFINE_"])) == expected
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

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "File includes injecting forms inline" do
    input = """
      -include("test/files/include1.hrl").
      -include("include3.hrl").
      """

    expected = """
      # Begin included file: test/files/include1.hrl


      defmacrop erlconst_INCLUDE1_CONST() do
        quote do
          1
        end
      end


      # Begin included file: files2/include2.hrl


      defmacrop erlconst_INCLUDE2_CONST() do
        quote do
          2
        end
      end


      # End included file: files2/include2.hrl


      # End included file: test/files/include1.hrl


      # Begin included file: include3.hrl


      defmacrop erlconst_INCLUDE3_CONST() do
        quote do
          3
        end
      end


      # End included file: include3.hrl
      """

    assert Erl2ex.convert_str!(input, Keyword.merge(@opts, [include_dir: "test/files"])) == expected
  end


  test "Library include" do
    input = """
      -include_lib("kernel/include/file.hrl").
      """

    output = Erl2ex.convert_str!(input)

    assert String.contains?(output, "Record.defrecordp :erlrecord_file_info")
  end


  test "File include path with an environment variable" do
    System.put_env("ERL2EX_TEST_FILES", "test/files")

    input = """
      -include("$ERL2EX_TEST_FILES/include3.hrl").
      """

    expected = """
      # Begin included file: test/files/include3.hrl


      defmacrop erlconst_INCLUDE3_CONST() do
        quote do
          3
        end
      end


      # End included file: test/files/include3.hrl
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Library include with an environment ariable" do
    System.put_env("ERL2EX_LIBRARY_NAME", "kernel")

    input = """
      -include_lib("$ERL2EX_LIBRARY_NAME/include/file.hrl").
      """

    output = Erl2ex.convert_str!(input)

    assert String.contains?(output, "Record.defrecordp :erlrecord_file_info")
  end


  test "Redefine constant macro" do
    input = """
      -define(HELLO, 1).
      -define(HELLO, 2).
      foo() -> ?HELLO.
      """

    expected = """
      defmacrop erlmacro(name, args), do:
        {Module.get_attribute(__MODULE__, name), [], args}
      defmacrop erlmacro(name), do:
        {Module.get_attribute(__MODULE__, name), [], []}


      defmacrop erlconst_HELLO() do
        quote do
          1
        end
      end
      @erlconst_HELLO :erlconst_HELLO


      defmacrop erlconst2_HELLO() do
        quote do
          2
        end
      end
      @erlconst_HELLO :erlconst2_HELLO


      defp foo() do
        erlmacro(:erlconst_HELLO)
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Redefine function macro" do
    input = """
      -define(HELLO(X), 1 + X).
      -define(HELLO(X), 2 + X).
      foo() -> ?HELLO(3).
      """

    expected = """
      defmacrop erlmacro(name, args), do:
        {Module.get_attribute(__MODULE__, name), [], args}
      defmacrop erlmacro(name), do:
        {Module.get_attribute(__MODULE__, name), [], []}


      defmacrop erlmacro_HELLO(x) do
        quote do
          1 + unquote(x)
        end
      end
      @erlmacro_HELLO :erlmacro_HELLO


      defmacrop erlmacro2_HELLO(x) do
        quote do
          2 + unquote(x)
        end
      end
      @erlmacro_HELLO :erlmacro2_HELLO


      defp foo() do
        erlmacro(:erlmacro_HELLO, [3])
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


end
