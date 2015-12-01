defmodule ErlParseTest do
  use ExUnit.Case
  doctest Erl2ex.ErlParse


  test "basic features in the test1 fixture" do
    input = TestFixtures.test1_erl_source
    expected = TestFixtures.test1_erl_module
    assert Erl2ex.ErlParse.from_str(input) == expected
  end

end
