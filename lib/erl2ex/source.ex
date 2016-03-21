
defmodule Erl2ex.Source do

  @moduledoc """
  Erl2ex.Source is a process that produces Erlang source, normally reading
  files from the file system.
  """


  @type t :: pid()


  @spec start_link(list) :: t

  def start_link(opts) do
    {:ok, pid} = GenServer.start_link(__MODULE__, opts)
    pid
  end


  def read_source(source, path) do
    source
      |> GenServer.call({:read_source, path})
      |> handle_result
  end


  def read_include(source, path, cur_dir) do
    source
      |> GenServer.call({:read_include, path, cur_dir})
      |> handle_result
  end


  def read_lib_include(source, lib, path) do
    source
      |> GenServer.call({:read_lib_include, lib, path})
      |> handle_result
  end


  def stop(source) do
    GenServer.cast(source, {:stop})
  end


  defp handle_result({:ok, data, path}), do: {data, path}
  defp handle_result({:error, code, path}) do
    raise CompileError,
      file: path,
      line: :unknown,
      description: "Error #{code} while reading source file"
  end


  use GenServer

  defmodule State do
    @moduledoc false
    defstruct(
      source_dir: nil,
      source_data: %{},
      include_dirs: [],
      include_data: %{},
      lib_data: %{}
    )
  end


  def init(opts) do
    source_dir = Keyword.get(opts, :source_dir, nil)
    source_data = opts
      |> Keyword.get_values(:source_data)
      |> Enum.reduce(%{}, &(add_to_map(&2, &1)))
    include_dirs = opts
      |> Keyword.get_values(:include_dir)
      |> Enum.reduce([], &([&1 | &2]))
    include_data = opts
      |> Keyword.get_values(:include_data)
      |> Enum.reduce(%{}, &(add_to_map(&2, &1)))
    lib_data = opts
      |> Keyword.get_values(:lib_data)
      |> Enum.reduce(%{}, &(add_to_map(&2, &1)))

    {:ok,
      %State{
        source_dir: source_dir,
        source_data: source_data,
        include_dirs: include_dirs,
        include_data: include_data,
        lib_data: lib_data,
      }
    }
  end


  def handle_call(
    {:read_source, path},
    _from,
    %State{source_dir: source_dir, source_data: source_data} = state)
  do
    dirs = if source_dir == nil, do: [], else: [source_dir]
    result = read_impl(path, source_data, dirs)
    {:reply, result, state}
  end

  def handle_call(
    {:read_include, path, cur_dir},
    _from,
    %State{include_dirs: include_dirs, include_data: include_data} = state)
  do
    dirs = include_dirs
    if cur_dir != nil, do: dirs = [cur_dir | dirs]
    dirs = [File.cwd! | dirs]
    result = read_impl(path, include_data, dirs)
    {:reply, result, state}
  end

  def handle_call(
    {:read_lib_include, lib, path},
    _from,
    %State{lib_data: lib_data} = state)
  do
    case :code.lib_dir(lib) do
      {:error, code} ->
        {:reply, {:error, code, path}, state}
      lib_dir ->
        result = read_impl(path, lib_data, [lib_dir])
        {:reply, result, state}
    end
  end


  def handle_cast({:stop}, state) do
    {:stop, :normal, state}
  end


  defp read_impl(path, data_map, search_dirs) do
    case Map.fetch(data_map, path) do
      {:ok, data} when is_binary(data) ->
        {:ok, data, path}
      {:ok, io} when is_pid(io) ->
        data = io |> IO.read(:all) |> IO.chardata_to_string
        {:ok, data, path}
      :error ->
        Enum.find_value(search_dirs, {:error, :not_found, path}, fn dir ->
          actual_path = Path.expand(path, dir)
          if File.exists?(actual_path) do
            case File.read(actual_path) do
              {:ok, data} -> {:ok, data, actual_path}
              {:error, code} -> {:error, code, path}
            end
          else
            false
          end
        end)
    end
  end


  defp add_to_map(map, value) when is_binary(value), do:
    Map.put(map, nil, value)
  defp add_to_map(map, value) when is_map(value), do:
    Map.merge(map, value)

end
