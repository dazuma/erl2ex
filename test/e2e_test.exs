
defmodule E2ETest do
  use ExUnit.Case

  import Erl2ex.TestHelper


  @tag :e2e
  @tag :e2e_poolboy
  test "poolboy" do
    download_project("poolboy", "https://github.com/devinus/poolboy.git")
    clean_dir("poolboy", "src_ex")
    convert_dir("poolboy", "src", "src_ex")
    copy_dir("poolboy", "test", "src_ex")
    compile_dir("poolboy", "src_ex", display_output: true)
    run_eunit_tests([:poolboy_tests], "poolboy", "src_ex", display_output: true)
  end


  @tag :e2e
  @tag :e2e_jsx
  test "jsx" do
    download_project("jsx", "https://github.com/talentdeficit/jsx.git")
    clean_dir("jsx", "src_ex")
    convert_dir("jsx", "src", "src_ex")
    compile_dir("jsx", "src_ex", display_output: true)
  end


  # Not yet working
  @tag :skip
  @tag :e2e_elixir
  test "elixir" do
    download_project("elixir", "https://github.com/elixir-lang/elixir.git")
    clean_dir("elixir", "lib/elixir/src_ex")
    convert_dir("elixir", "lib/elixir/src", "lib/elixir/src_ex")

    # elixir_bootstrap.erl generates __info__ functions so can't be converted
    File.rm!(project_path("elixir", "lib/elixir/src_ex/elixir_bootstrap.ex"))
    File.cp!(project_path("elixir", "lib/elixir/src/elixir_bootstrap.erl"),
        project_path("elixir", "lib/elixir/src_ex/elixir_bootstrap.erl"))

    copy_dir("elixir", "lib/elixir/test/erlang", "lib/elixir/src_ex")
    compile_dir("elixir", "lib/elixir/src_ex", display_output: true)
  end


end
