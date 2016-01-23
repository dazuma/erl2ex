defmodule Erl2ex.TestHelper do

  @e2e_files_dir "tmp/e2e"


  def download_project(name, url) do
    File.mkdir_p!(@e2e_files_dir)
    if File.dir?(project_path(name, ".git")) do
      run_cmd("git", ["pull"])
    else
      run_cmd("git", ["clone", url])
    end
  end


  def clean_dir(name, path) do
    File.rm_rf!(project_path(name, path))
    File.mkdir_p!(project_path(name, path))
  end


  def convert_dir(name, src_path, dest_path, opts \\ []) do
    File.mkdir_p!(project_path(name, dest_path))
    Erl2ex.convert_dir!(project_path(name, src_path), project_path(name, dest_path), opts)
  end


  def copy_dir(name, src_path, dest_path) do
    File.mkdir_p!(project_path(name, dest_path))
    File.cp_r!(project_path(name, src_path), project_path(name, dest_path))
  end


  def compile_dir(name, path, opts \\ []) do
    if Path.wildcard("#{project_path(name, path)}/*.ex") != [] do
      run_cmd("elixirc", [{"*.ex"}],
          Keyword.merge(opts, name: name, path: path, DEFINE_TEST: "true"))
    end
    if Path.wildcard("#{project_path(name, path)}/*.erl") != [] do
      run_cmd("erlc", ["-DTEST", {"*.erl"}],
          Keyword.merge(opts, name: name, path: path))
    end
  end


  def run_eunit_tests(tests, name, path, opts \\ []) do
    tests |> Enum.each(fn test ->
      run_elixir(":ok = :eunit.test(:#{test})",
          Keyword.merge(opts, name: name, path: path))
    end)
  end


  def run_elixir(cmd, opts \\ []) do
    run_cmd("elixir", ["-e", cmd], opts)
  end


  def run_cmd(cmd, args, opts \\ []) do
    name = Keyword.get(opts, :name)
    path = Keyword.get(opts, :path)
    cd = Keyword.get(opts, :cd, project_path(name, path))
    display_output = Keyword.get(opts, :display_output)
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
    output = case System.cmd(cmd, args, cd: cd, env: env, stderr_to_stdout: true) do
      {str, 0} -> str
      {str, code} ->
        raise "Error #{code} when running command #{cmd} #{inspect(args)}\n#{str}"
    end
    if display_output do
      IO.puts(output)
    end
    output
  end


  def project_path(name, path \\ nil)

  def project_path(nil, nil) do
    @e2e_files_dir
  end
  def project_path(name, nil) do
    "#{@e2e_files_dir}/#{name}"
  end
  def project_path(name, path) do
    "#{@e2e_files_dir}/#{name}/#{path}"
  end


  defmodule Result do
    defstruct(
      output: nil,
      module: nil
    )
  end


  def test_conversion(input, opts) do
    output = Erl2ex.convert_str!(input, opts)
    test_num = :erlang.unique_integer([:positive])
    module = :"Elixir.Erl2ex.TestModule#{test_num}"
    module_name = module |> Module.split |> Enum.join(".")
    Code.eval_string "defmodule #{module_name} do\n#{output}\nend"
    %Result{output: output, module: module}
  end


end


ExUnit.configure exclude: [:e2e, :dummy]
ExUnit.start()
