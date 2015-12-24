defmodule TypeTest do
  use ExUnit.Case


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

    assert Erl2ex.convert_str(input) == expected
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

    assert Erl2ex.convert_str(input) == expected
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

    assert Erl2ex.convert_str(input) == expected
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

      @typep type4() :: -1 .. 10
      """

    assert Erl2ex.convert_str(input) == expected
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

    assert Erl2ex.convert_str(input) == expected
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

    assert Erl2ex.convert_str(input) == expected
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

    assert Erl2ex.convert_str(input) == expected
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

      @typep type4() :: <<_ :: 10>>

      @typep type5() :: <<_ :: _ * 8>>

      @typep type6() :: <<_ :: 10, _ :: _ * 8>>
      """

    assert Erl2ex.convert_str(input) == expected
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

    assert Erl2ex.convert_str(input) == expected
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

    assert Erl2ex.convert_str(input) == expected
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

    assert Erl2ex.convert_str(input) == expected
  end


  test "Records" do
    input = """
      -type type1() :: #myrecord{field1 :: any(), field2 :: atom() | integer()}.
      """

    expected = """
      @typep type1() :: record(:myrecord, field1: any(), field2: atom() | integer())
      """

    assert Erl2ex.convert_str(input) == expected
  end


end
