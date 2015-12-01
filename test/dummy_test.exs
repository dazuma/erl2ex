defmodule DummyTest do
  use ExUnit.Case

  @tag :skip
  test "dummy1" do
    "-spec foo(integer()) -> integer().\n"
      |> Erl2ex.ErlParse.from_string
      |> inspect
      |> IO.puts
  end

end
