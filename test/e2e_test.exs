
defmodule E2ETest do
  use ExUnit.Case

  import Erl2ex.TestHelper


  # Libraries that are working


  @tag :e2e
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
    run_eunit_tests(
        [:ec_plists],
        "erlware_commons", "src_ex", display_output: true)
  end


  @tag :e2e
  test "getopt" do
    download_project("getopt", "https://github.com/jcomellas/getopt.git")
    clean_dir("getopt", "src_ex")
    convert_dir("getopt", "src", "src_ex")
    copy_dir("getopt", "test", "src_ex")
    compile_dir("getopt", "src_ex", display_output: true)
    run_eunit_tests(
        [:getopt_test],
        "getopt", "src_ex", display_output: true)
  end


  @tag :e2e
  test "gproc" do
    download_project("gproc", "https://github.com/uwiger/gproc.git")
    clean_dir("gproc", "src_ex")
    convert_dir("gproc", "src", "src_ex",
        include_dir: project_path("gproc", "include"),
        auto_export_suffix: "_test_",
        auto_export_suffix: "_test")
    copy_dir("gproc", "test", "src_ex", ["gproc_tests.erl", "gproc_test_lib.erl"])
    copy_file("gproc", "src/gproc.app.src", "src_ex/gproc.app")
    compile_dir("gproc", "src_ex", display_output: true)
    run_eunit_tests(
        [:gproc_tests],
        "gproc", "src_ex", display_output: true)
  end


  @tag :e2e
  test "idna" do
    download_project("idna", "https://github.com/benoitc/erlang-idna.git")
    clean_dir("idna", "src_ex")
    convert_dir("idna", "src", "src_ex")
    copy_dir("idna", "test", "src_ex")
    compile_dir("idna", "src_ex", display_output: true)
    run_eunit_tests(
        [:idna_test],
        "idna", "src_ex", display_output: true)
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
  test "mochiweb" do
    download_project("mochiweb", "https://github.com/mochi/mochiweb.git")
    clean_dir("mochiweb", "src_ex")
    convert_dir("mochiweb", "src", "src_ex",
        include_dir: project_path("mochiweb", "include"))
    copy_dir("mochiweb", "test", "src_ex")
    compile_dir("mochiweb", "src_ex", display_output: true)
    run_eunit_tests(
        [
          :mochiweb_base64url_tests,
          :mochiweb_html_tests,
          :mochiweb_http_tests,
          :mochiweb_request_tests,
          :mochiweb_socket_server_tests,
          :mochiweb_tests,
          :mochiweb_websocket_tests
        ],
        "mochiweb", "src_ex", display_output: true)
  end


  @tag :e2e
  test "poolboy" do
    download_project("poolboy", "https://github.com/devinus/poolboy.git")
    clean_dir("poolboy", "src_ex")
    convert_dir("poolboy", "src", "src_ex")
    copy_dir("poolboy", "test", "src_ex")
    compile_dir("poolboy", "src_ex", display_output: true)
    run_eunit_tests(
        [:poolboy],
        "poolboy", "src_ex", display_output: true)
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


  # Fails because a macro appears as a record name.
  @tag :skip
  test "bbmustache" do
    download_project("bbmustache", "https://github.com/soranoba/bbmustache.git")
    clean_dir("bbmustache", "src_ex")
    convert_dir("bbmustache", "src", "src_ex")
    copy_dir("bbmustache", "test", "src_ex")
    compile_dir("bbmustache", "src_ex", display_output: true)
    run_eunit_tests(
        [:bbmustache_tests],
        "bbmustache", "src_ex", display_output: true)
  end


  # Fails because cowlib fails
  @tag :skip
  test "cowboy" do
    download_project("cowboy", "https://github.com/ninenines/cowboy.git")
    download_project("cowlib", "https://github.com/ninenines/cowlib.git")
    download_project("ranch", "https://github.com/ninenines/ranch.git")
    clean_dir("cowboy", "src_ex")
    convert_dir("cowboy", "src", "src_ex",
        lib_dir: %{cowlib: project_path("cowlib"), ranch: project_path("ranch")})
    compile_dir("cowboy", "src_ex", display_output: true)
    # Not sure how to run tests
  end


  # Fails because a comprehension contains a macro invocation
  @tag :skip
  test "cowlib" do
    download_project("ranch", "https://github.com/ninenines/cowlib.git")
    clean_dir("cowlib", "src_ex")
    convert_dir("cowlib", "src", "src_ex",
        include_dir: project_path("cowlib", "include"))
    compile_dir("cowlib", "src_ex", display_output: true)
    # Not sure how to run tests
  end


  # In progress. Doesn't run tests properly yet because it gets confused between
  # the compiled modules and the modules from the installed Elixir runtime.
  # TODO: Try running the tests using erl, to disable the Elixir runtime.
  @tag :skip
  test "elixir" do
    download_project("elixir", "https://github.com/elixir-lang/elixir.git")
    clean_dir("elixir", "lib/elixir/src_ex")
    convert_dir("elixir", "lib/elixir/src", "lib/elixir/src_ex")

    # elixir_bootstrap.erl generates __info__ functions so can't be converted for now
    File.rm!(project_path("elixir", "lib/elixir/src_ex/elixir_bootstrap.ex"))
    File.cp!(project_path("elixir", "lib/elixir/src/elixir_bootstrap.erl"),
        project_path("elixir", "lib/elixir/src_ex/elixir_bootstrap.erl"))

    copy_dir("elixir", "lib/elixir/test/erlang", "lib/elixir/src_ex/test_erlang")

    # Compile each elixir file separately; otherwise newly compiled modules will
    # be added to the VM, causing compatibility issues between old and new.
    compile_dir_individually("elixir", "lib/elixir/src_ex", display_output: true, display_cmd: true)

    compile_dir("elixir", "lib/elixir/src_ex/test_erlang", display_output: true, display_cmd: true)
    copy_dir("elixir", "lib/elixir/src_ex/test_erlang", "lib/elixir/src_ex")

    #run_eunit_tests(
    #    [
    #      :atom_test,
    #      :control_test,
    #      :function_test,
    #      :match_test,
    #      :module_test,
    #      :operators_test,
    #      :string_test,
    #      :tokenizer_test
    #    ],
    #    "elixir", "src_ex", display_output: true, display_cmd: true)
  end


  # Fails because a binary literal contains a macro invocation returning a list.
  @tag :skip
  test "eredis" do
    download_project("eredis", "https://github.com/wooga/eredis.git")
    clean_dir("eredis", "src_ex")
    convert_dir("eredis", "src", "src_ex",
        include_dir: project_path("eredis", "include"))
    copy_dir("eredis", "test", "src_ex")
    compile_dir("eredis", "src_ex", display_output: true)
    run_eunit_tests(
        [:eredis_parser_tests, :eredis_sub_tests, :eredis_tests],
        "eredis", "src_ex", display_output: true)
  end


  # Fails because a fully qualified macro appears in a typespec
  @tag :skip
  test "goldrush" do
    download_project("goldrush", "https://github.com/DeadZen/goldrush.git")
    clean_dir("goldrush", "src_ex")
    convert_dir("goldrush", "src", "src_ex",
        auto_export_suffix: "_test_",
        auto_export_suffix: "_test")
    compile_dir("goldrush", "src_ex", display_output: true)
    run_eunit_tests(
        [:glc],
        "goldrush", "src_ex", display_output: true)
  end


  # Fails because of a strange missing file in the public_key application.
  @tag :skip
  test "ssl_verify_fun" do
    download_project("ssl_verify_fun", "https://github.com/deadtrickster/ssl_verify_fun.erl.git")
    clean_dir("ssl_verify_fun", "src_ex")
    convert_dir("ssl_verify_fun", "src", "src_ex")
    copy_dir("ssl_verify_fun", "test", "src_ex")
    compile_dir("ssl_verify_fun", "src_ex", display_output: true)
    run_eunit_tests(
        [:ssl_verify_fingerprint_tests, :ssl_verify_hostname_tests, :ssl_verify_pk_tests],
        "ssl_verify_fun", "src_ex", display_output: true)
  end

end
