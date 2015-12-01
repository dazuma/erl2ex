defmodule ExWriteTest do
  use ExUnit.Case
  doctest Erl2ex.ExWrite


  test "basic features in the test1 fixture" do
    input = TestFixtures.test1_ex_module
    expected = TestFixtures.test1_ex_source
    assert Erl2ex.ExWrite.to_str(input) == expected
  end

end
