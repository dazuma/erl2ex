
defmodule E2ETest do
  use ExUnit.Case

  import Erl2ex.TestHelper


  @tag :e2e
  @tag :e2e_poolboy
  test "poolboy" do
    download_project("poolboy", "https://github.com/devinus/poolboy.git")
    clean_dir("poolboy", "ex")
    convert_dir("poolboy", "src", "ex")
    copy_dir("poolboy", "test", "ex")
    compile_dir("poolboy", "ex", display_output: true)
    run_eunit_tests([:poolboy_tests], "poolboy", "ex", display_output: true)
  end


  @tag :e2e
  @tag :e2e_elixir
  test "elixir" do
    download_project("elixir", "https://github.com/elixir-lang/elixir.git")
    clean_dir("elixir", "lib/elixir/ex")
    convert_dir("elixir", "lib/elixir/src", "lib/elixir/ex")

    # elixir_bootstrap.erl generates __info__ functions so can't be converted
    File.rm!(project_path("elixir", "lib/elixir/ex/elixir_bootstrap.ex"))
    File.cp!(project_path("elixir", "lib/elixir/src/elixir_bootstrap.erl"),
        project_path("elixir", "lib/elixir/ex/elixir_bootstrap.erl"))

    copy_dir("elixir", "lib/elixir/test/erlang", "lib/elixir/ex")
    compile_dir("elixir", "lib/elixir/ex", display_output: true)
  end


end
