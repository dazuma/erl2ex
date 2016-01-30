defmodule StructureTest do
  use ExUnit.Case

  @opts [emit_file_headers: false]


  test "Module comments" do
    input = """
      %% This is an empty module.
      -module(foo).
      """

    expected = """
      ## This is an empty module.

      defmodule :foo do

      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Input does not end with a newline" do
    input = "-module(foo)."

    expected = """
      defmodule :foo do

      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Record operations" do
    input = """
      -record(foo, {field1, field2=123}).
      foo() ->
        A = #foo{field1="Ada"},
        B = A#foo{field2=234},
        C = #foo{field1="Lovelace", _=345},
        #foo{field1=D} = B,
        B#foo.field2.
      """

    expected = """
      require Record

      @erlrecordfields_foo [:field1, :field2]
      Record.defrecordp :erlrecord_foo, :foo, [field1: :undefined, field2: 123]


      defp foo() do
        a = erlrecord_foo(field1: 'Ada')
        b = erlrecord_foo(a, field2: 234)
        c = erlrecord_foo(field1: 'Lovelace', field2: 345)
        erlrecord_foo(field1: d) = b
        erlrecord_foo(b, :field2)
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Record queries" do
    input = """
      -record(foo, {field1, field2=123}).
      foo() ->
        #foo.field2,
        record_info(size, foo),
        record_info(fields, foo).
      """

    expected = """
      require Record

      defmacrop erlrecordsize(data_attr) do
        __MODULE__ |> Module.get_attribute(data_attr) |> Enum.count |> +(1)
      end

      defmacrop erlrecordindex(data_attr, field) do
        index = __MODULE__ |> Module.get_attribute(data_attr) |> Enum.find_index(&(&1 ==field))
        if index == nil, do: 0, else: index + 1
      end

      @erlrecordfields_foo [:field1, :field2]
      Record.defrecordp :erlrecord_foo, :foo, [field1: :undefined, field2: 123]


      defp foo() do
        erlrecordindex(:erlrecordfields_foo, :field2)
        erlrecordsize(:erlrecordfields_foo)
        @erlrecordfields_foo
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "on_load attribute" do
    input = """
      -on_load(foo/0).
      """

    expected = """
      @on_load :foo
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "vsn attribute" do
    input = """
      -vsn(123).
      """

    expected = """
      @vsn 123
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "behaviour attribute (british spelling)" do
    input = """
      -behaviour(gen_server).
      """

    expected = """
      @behaviour :gen_server
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "behavior attribute (american spelling)" do
    input = """
      -behavior(gen_server).
      """

    expected = """
      @behaviour :gen_server
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "callback attributes" do
    input = """
      -callback foo(A :: atom(), integer()) -> boolean()
        ; (A :: integer(), B :: atom()) -> 'hello' | boolean().
      -callback bar(A, B) -> A | B when A :: tuple(), B :: atom().
      """

    expected = """
      @callback foo(atom(), integer()) :: boolean()
      @callback foo(integer(), atom()) :: :hello | boolean()

      @callback bar(a, b) :: a | b when a: tuple(), b: atom()
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "file attribute" do
    input = """
      -file("myfile.erl", 10).
      """

    expected = """
      # File "myfile.erl" Line 10
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end

end
