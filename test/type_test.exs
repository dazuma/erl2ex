defmodule TypeTest do
  use ExUnit.Case

  @opts [emit_file_headers: false]


  test "Visibility" do
    input = """
      -type public_type() :: any().
      -opaque opaque_type(A) :: list(A).
      -type private_type() :: integer().
      -export_type([public_type/0, opaque_type/1]).
      """

    expected = """
      @type public_type() :: any()

      @opaque opaque_type(a) :: list(a)

      @typep private_type() :: integer()
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Misc base types" do
    input = """
      -type type1() :: any().
      -type type2() :: none().
      -type type3() :: pid().
      -type type4() :: port().
      -type type5() :: reference().
      -type type6() :: float().
      """

    expected = """
      @typep type1() :: any()

      @typep type2() :: none()

      @typep type3() :: pid()

      @typep type4() :: port()

      @typep type5() :: reference()

      @typep type6() :: float()
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Atom types" do
    input = """
      -type type1() :: atom().
      -type type2() :: hello.
      -type type3() :: '123'.
      """

    expected = """
      @typep type1() :: atom()

      @typep type2() :: :hello

      @typep type3() :: :"123"
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Integer types" do
    input = """
      -type type1() :: integer().
      -type type2() :: 42.
      -type type3() :: -42.
      -type type4() :: -1..10.
      """

    expected = """
      @typep type1() :: integer()

      @typep type2() :: 42

      @typep type3() :: -42

      @typep type4() :: -1..10
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Const types" do
    input = """
      -type type1() :: hello.
      -type type2() :: 42.
      """

    expected = """
      @typep type1() :: :hello

      @typep type2() :: 42
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "List types" do
    input = """
      -type type1() :: list().
      -type type2() :: [integer()].
      -type type3() :: list(integer()).
      -type type4() :: [].
      -type type5() :: [atom(),...].
      -type type6() :: nil().
      """

    expected = """
      @typep type1() :: list()

      @typep type2() :: list(integer())

      @typep type3() :: list(integer())

      @typep type4() :: []

      @typep type5() :: nonempty_list(atom())

      @typep type6() :: []
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Tuple types" do
    input = """
      -type type1() :: tuple().
      -type type2() :: {}.
      -type type3() :: {any()}.
      -type type4() :: {integer(), atom(), hello}.
      """

    expected = """
      @typep type1() :: tuple()

      @typep type2() :: {}

      @typep type3() :: {any()}

      @typep type4() :: {integer(), atom(), :hello}
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Bitstring types" do
    input = """
      -type type1() :: binary().
      -type type2() :: bitstring().
      -type type3() :: <<>>.
      -type type4() :: <<_:10>>.
      -type type5() :: <<_:_*8>>.
      -type type6() :: <<_:10,_:_*8>>.
      """

    expected = """
      @typep type1() :: binary()

      @typep type2() :: bitstring()

      @typep type3() :: <<>>

      @typep type4() :: <<_::10>>

      @typep type5() :: <<_::_*8>>

      @typep type6() :: <<_::10, _::_*8>>
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Function types" do
    input = """
      -type type1() :: fun().
      -type type2() :: fun((...) -> any()).
      -type type3() :: fun(() -> integer()).
      -type type4() :: fun((atom(), atom()) -> integer()).
      """

    expected = """
      @typep type1() :: fun()

      @typep type2() :: (... -> any())

      @typep type3() :: (() -> integer())

      @typep type4() :: (atom(), atom() -> integer())
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Map types" do
    input = """
      -type type1() :: map().
      -type type2() :: \#{}.
      -type type3() :: \#{atom() => integer()}.
      """

    expected = """
      @typep type1() :: map()

      @typep type2() :: %{}

      @typep type3() :: %{atom() => integer()}
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Unions" do
    input = """
      -type type1() :: atom() | integer().
      -type type2() :: true | false | nil.
      """

    expected = """
      @typep type1() :: atom() | integer()

      @typep type2() :: true | false | nil
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Records" do
    input = """
      -record(myrecord, {field1=hello :: any(), field2 :: tuple() | integer(), field3}).
      -type type1() :: #myrecord{}.
      -type type2() :: #myrecord{field1 :: string()}.
      """

    expected = """
      require Record

      @erlrecordfields_myrecord [:field1, :field2, :field3]
      Record.defrecordp :erlrecord_myrecord, :myrecord, [field1: :hello, field2: :undefined, field3: :undefined]

      @typep type1() :: record(:erlrecord_myrecord, field1: any(), field2: :undefined | tuple() | integer(), field3: term())

      @typep type2() :: record(:erlrecord_myrecord, field1: char_list(), field2: :undefined | tuple() | integer(), field3: term())
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Unknown parameters" do
    input = """
      -type type1(T) :: list(T) | {_}.
      """

    expected = """
      @typep type1(t) :: list(t) | {any()}
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Custom type" do
    input = """
      -type type1() :: atom().
      -type type2() :: type1() | integer().
      """

    expected = """
      @typep type1() :: atom()

      @typep type2() :: type1() | integer()
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


  test "Remote type" do
    input = """
      -type type1() :: supervisor:startchild_ret().
      """

    expected = """
      @typep type1() :: :supervisor.startchild_ret()
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
      -spec foo(A, B) -> A | B | list(T).
      foo(A, B) -> A.
      """

    expected = """
      @spec foo(a, b) :: a | b | list(t) when a: any(), b: any(), t: any()


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


  test "Specs with guards constraining other guards" do
    input = """
      -spec foo() -> A when A :: fun(() -> B), B :: atom().
      foo() -> fun () -> ok end.
      """

    expected = """
      @spec foo() :: a when a: (() -> b), b: atom()


      defp foo() do
        fn -> :ok end
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


  test "Specs for function that gets renamed" do
    input = """
      -spec to_string(any()) -> any().
      to_string(A) -> A.
      """

    expected = """
      @spec func_to_string(any()) :: any()


      defp func_to_string(a) do
        a
      end
      """

    assert Erl2ex.convert_str!(input, @opts) == expected
  end


end
