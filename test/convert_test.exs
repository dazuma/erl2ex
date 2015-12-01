defmodule ConvertTest do
  use ExUnit.Case
  doctest Erl2ex.Convert


  test "basic features in the test1 fixture" do
    input = TestFixtures.test1_erl_module
    expected = TestFixtures.test1_ex_module
    assert Erl2ex.Convert.module(input) == expected
  end

end
