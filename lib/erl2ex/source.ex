defmodule Erl2ex.Source do
  @moduledoc """
  Erl2ex.Source is a process that produces Erlang source, normally reading
  files from the file system.
  """

  @typedoc """
  The ProcessID of a source process.
  """

  @type t :: pid()

  @doc """
  Starts a source and returns its PID.
  """

  @spec start_link(list) :: t

  def start_link(opts) do
    {:ok, pid} = GenServer.start_link(__MODULE__, opts)
    pid
  end

  @doc """
  Reads the source file at the given path or symbolic location, and returns a
  tuple comprising the data in the file and the full path to it.
  """

  @spec read_source(t, Erl2ex.file_id()) :: {String.t(), Erl2ex.file_id()}

  def read_source(source, path) do
    source
    |> GenServer.call({:read_source, path})
    |> handle_result
  end

  @doc """
  Reads the include file at the given path, given a context directory, and
  returns a tuple comprising the data in the file and the full path to it.
  """

  @spec read_include(t, Path.t(), Path.t() | nil) :: {String.t(), Path.t()}

  def read_include(source, path, cur_dir) do
    source
    |> GenServer.call({:read_include, path, cur_dir})
    |> handle_result
  end

  @doc """
  Reads the include file at the given path, given a context library, and
  returns a tuple comprising the data in the file and the full path to it.
  """

  @spec read_lib_include(t, atom, Path.t()) :: {String.t(), Path.t()}

  def read_lib_include(source, lib, path) do
    source
    |> GenServer.call({:read_lib_include, lib, path})
    |> handle_result
  end

  @doc """
  Stops the source process.
  """

  @spec stop(t) :: :ok

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
      lib_dirs: %{},
      lib_data: %{}
    )
  end

  def init(opts) do
    source_dir = Keyword.get(opts, :source_dir, nil)

    source_data =
      opts
      |> Keyword.get_values(:source_data)
      |> Enum.reduce(%{}, &add_to_map(&2, &1))

    include_dirs =
      opts
      |> Keyword.get_values(:include_dir)
      |> Enum.reduce([], &[&1 | &2])

    include_data =
      opts
      |> Keyword.get_values(:include_data)
      |> Enum.reduce(%{}, &add_to_map(&2, &1))

    lib_dirs =
      opts
      |> Keyword.get_values(:lib_dir)
      |> Enum.reduce(%{}, &add_to_map(&2, &1))

    lib_data =
      opts
      |> Keyword.get_values(:lib_data)
      |> Enum.reduce(%{}, &add_to_map(&2, &1))

    {:ok,
     %State{
       source_dir: source_dir,
       source_data: source_data,
       include_dirs: include_dirs,
       include_data: include_data,
       lib_dirs: lib_dirs,
       lib_data: lib_data
     }}
  end

  def handle_call(
        {:read_source, path},
        _from,
        %State{source_dir: source_dir, source_data: source_data} = state
      ) do
    dirs = if source_dir == nil, do: [], else: [source_dir]
    result = read_impl(path, source_data, dirs)
    {:reply, result, state}
  end

  def handle_call(
        {:read_include, path, cur_dir},
        _from,
        %State{include_dirs: include_dirs, include_data: include_data} = state
      ) do
    dirs =
      if cur_dir == nil do
        include_dirs
      else
        [cur_dir | include_dirs]
      end

    dirs = [File.cwd!() | dirs]
    result = read_impl(path, include_data, dirs)
    {:reply, result, state}
  end

  def handle_call(
        {:read_lib_include, lib, path},
        _from,
        %State{lib_data: lib_data, lib_dirs: lib_dirs} = state
      ) do
    case get_lib_dir(lib_dirs, lib) do
      {:error, code} ->
        {:reply, {:error, code, path}, state}

      {:ok, lib_dir} ->
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
        data = io |> IO.read(:all) |> IO.chardata_to_string()
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

  defp get_lib_dir(lib_dirs, lib) do
    case Map.fetch(lib_dirs, lib) do
      {:ok, dir} ->
        {:ok, dir}

      :error ->
        case :code.lib_dir(lib) do
          {:error, code} -> {:error, code}
          dir -> {:ok, dir}
        end
    end
  end

  defp add_to_map(map, value) when is_map(value), do: Map.merge(map, value)
  defp add_to_map(map, {key, value}), do: Map.put(map, key, value)
  defp add_to_map(map, value), do: Map.put(map, nil, value)
end
