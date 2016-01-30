
defmodule E2ETest do
  use ExUnit.Case

  import Erl2ex.TestHelper


  # Libraries that are working

  @tag :e2e
  test "poolboy" do
    download_project("poolboy", "https://github.com/devinus/poolboy.git")
    clean_dir("poolboy", "src_ex")
    convert_dir("poolboy", "src", "src_ex")
    copy_dir("poolboy", "test", "src_ex")
    compile_dir("poolboy", "src_ex", display_output: true)
    run_eunit_tests([:poolboy], "poolboy", "src_ex", display_output: true)
  end


  @tag :e2e
  test "jsx" do
    download_project("jsx", "https://github.com/talentdeficit/jsx.git")
    clean_dir("jsx", "src_ex")
    convert_dir("jsx", "src", "src_ex", auto_export_suffix: "_test_")
    compile_dir("jsx", "src_ex", display_output: true)
    run_eunit_tests(
      [
        :jsx,
        :jsx_config,
        :jsx_decoder,
        :jsx_encoder,
        :jsx_parser,
        :jsx_to_json,
        :jsx_to_term,
        :jsx_verify
      ],
      "jsx", "src_ex", display_output: true)
  end


  @tag :e2e
  test "ranch" do
    download_project("ranch", "https://github.com/ninenines/ranch.git")
    clean_dir("ranch", "src_ex")
    convert_dir("ranch", "src", "src_ex")
    compile_dir("ranch", "src_ex", display_output: true)
    # Not sure how to run tests
  end


  # Libraries that are not yet working

  # Fails because a comprehension has an implicit generator
  @tag :skip
  test "gproc" do
    download_project("gproc", "https://github.com/uwiger/gproc.git")
    clean_dir("gproc", "src_ex")
    convert_dir("gproc", "src", "src_ex",
        include_dir: project_path("gproc", "include"),
        auto_export_suffix: "_test_",
        auto_export_suffix: "_test")
    compile_dir("gproc", "src_ex", display_output: true)
    run_eunit_tests([:gproc_tests, :gproc_dist_tests], "gproc", "src_ex", display_output: true)
  end


  # Fails because a macro appears in a typespec
  @tag :skip
  test "goldrush" do
    download_project("goldrush", "https://github.com/DeadZen/goldrush.git")
    clean_dir("goldrush", "src_ex")
    convert_dir("goldrush", "src", "src_ex",
        auto_export_suffix: "_test_",
        auto_export_suffix: "_test")
    compile_dir("goldrush", "src_ex", display_output: true)
    run_eunit_tests([:glc], "goldrush", "src_ex", display_output: true)
  end


  # Fails because a macro appears in a typespec
  @tag :skip
  test "getopt" do
    download_project("getopt", "https://github.com/jcomellas/getopt.git")
    clean_dir("getopt", "src_ex")
    convert_dir("getopt", "src", "src_ex", auto_export_suffix: "_test_")
    compile_dir("getopt", "src_ex", display_output: true)
    run_eunit_tests([:getopt_test], "getopt", "src_ex", display_output: true)
  end


  # Fails due to incorrect @file attribute
  @tag :skip
  test "erlware_commons" do
    download_project("erlware_commons", "https://github.com/erlware/erlware_commons.git")
    clean_dir("erlware_commons", "src_ex")
    convert_dir("erlware_commons", "src", "src_ex",
        include_dir: project_path("erlware_commons", "include"),
        auto_export_suffix: "_test_",
        auto_export_suffix: "_test")
    copy_dir("erlware_commons", "test", "src_ex")
    compile_dir("erlware_commons", "src_ex",
        display_output: true,
        DEFINE_namespaced_types: "true")
    run_eunit_tests([:ec_plists], "erlware_commons", "src_ex", display_output: true)
  end


  # Fails because a macro appears as a record name.
  @tag :skip
  test "bbmustache" do
    download_project("bbmustache", "https://github.com/soranoba/bbmustache.git")
    clean_dir("bbmustache", "src_ex")
    convert_dir("bbmustache", "src", "src_ex")
    copy_dir("bbmustache", "test", "src_ex")
    compile_dir("bbmustache", "src_ex", display_output: true)
    run_eunit_tests([:bbmustache_tests], "bbmustache", "src_ex", display_output: true)
  end


  # Fails because there is a capture with a variable arity in elixir_dispatch.erl
  @tag :skip
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
