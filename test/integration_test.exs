defmodule IntegrationTestHelper do

  @integration_files_dir "integration_files"


  def download_project(name, url) do
    File.mkdir_p!(@integration_files_dir)
    if File.dir?(project_dir(name, ".git")) do
      run_cmd("git", ["pull"])
    else
      run_cmd("git", ["clone", url])
    end
  end


  def clean_dir(name, path) do
    File.rm_rf!(project_dir(name, path))
    File.mkdir_p!(project_dir(name, path))
  end


  def run_conversion(name, src_path, dest_path, opts \\ []) do
    File.mkdir_p!(project_dir(name, dest_path))
    Erl2ex.convert_dir!(project_dir(name, src_path), project_dir(name, dest_path), opts)
  end


  def copy_files(name, src_path, dest_path) do
    File.mkdir_p!(project_dir(name, dest_path))
    File.cp_r!(project_dir(name, src_path), project_dir(name, dest_path))
  end


  def compile_dir(name, path) do
    run_cmd("elixirc", [{"*.ex"}], name: name, path: path, DEFINE_TEST: "true")
    run_cmd("erlc", ["-DTEST", {"*.erl"}], name: name, path: path)
  end


  def run_eunit_tests(tests, name, path) do
    tests |> Enum.each(fn test ->
      run_elixir(":ok = :eunit.test(:#{test})", name: name, path: path)
    end)
  end


  def run_elixir(cmd, opts \\ []) do
    run_cmd("elixir", ["-e", cmd], opts)
  end


  def run_cmd(cmd, args, opts \\ []) do
    name = Keyword.get(opts, :name)
    path = Keyword.get(opts, :path)
    cd = Keyword.get(opts, :cd, project_dir(name, path))
    env = opts |> Enum.filter_map(
      fn {k, _} -> Regex.match?(~r/^[A-Z]/, Atom.to_string(k)) end,
      fn {k, v} -> {Atom.to_string(k), v} end
    )
    args = args |> Enum.flat_map(fn
      {wildcard} ->
        "#{cd}/#{wildcard}"
          |> Path.wildcard
          |> Enum.map(&(String.replace_prefix(&1, "#{cd}/", "")))
      str -> [str]
    end)
    case System.cmd(cmd, args, cd: cd, env: env, stderr_to_stdout: true) do
      {str, 0} -> str
      {str, code} ->
        raise "Error #{code} when running command #{cmd} #{inspect(args)}\n#{str}"
    end
  end


  def project_dir(name, path \\ nil)

  def project_dir(nil, nil) do
    @integration_files_dir
  end
  def project_dir(name, nil) do
    "#{@integration_files_dir}/#{name}"
  end
  def project_dir(name, path) do
    "#{@integration_files_dir}/#{name}/#{path}"
  end

end


defmodule IntegrationTest do
  use ExUnit.Case

  import IntegrationTestHelper


  @tag :integration
  @tag :integration_poolboy
  test "poolboy" do
    download_project("poolboy", "https://github.com/devinus/poolboy.git")
    clean_dir("poolboy", "ex")
    run_conversion("poolboy", "src", "ex")
    copy_files("poolboy", "test", "ex")
    compile_dir("poolboy", "ex")
    run_eunit_tests([:poolboy_tests], "poolboy", "ex")
  end


  @tag :integration
  @tag :integration_elixir
  test "elixir" do
    download_project("elixir", "https://github.com/elixir-lang/elixir.git")
    clean_dir("elixir", "lib/elixir/ex")
    run_conversion("elixir", "lib/elixir/src", "lib/elixir/ex")
    copy_files("elixir", "lib/elixir/test/erlang", "lib/elixir/ex")
    # Not yet working: elixir_bootstrap.erl generates __info__ functions
    # compile_dir("elixir", "lib/elixir/ex")
  end


end
