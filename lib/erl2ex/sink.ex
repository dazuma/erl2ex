
defmodule Erl2ex.Sink do

  @moduledoc """
  Erl2ex.Sink is a process that consumes generated Elixir source, normally
  writing files to the file system.
  """


  @typedoc """
  The ProcessID of a sink process.
  """

  @type t :: pid()


  @typedoc """
  A file identifier, which may be a filesystem path or a symbolic id.
  """

  @type file_id :: Path.t | atom


  @doc """
  Starts a sink and returns its PID.
  """

  @spec start_link(list) :: t

  def start_link(opts \\ []) do
    {:ok, pid} = GenServer.start_link(__MODULE__, opts)
    pid
  end


  @doc """
  Writes data to a sink, at the given path.
  """

  @spec write(t, file_id, String.t) :: :ok | {:error, term}

  def write(sink, path, str) do
    GenServer.call(sink, {:write, path, str})
  end


  @doc """
  Gets the file contents written to the given ID.

  Available only if the `allow_get` configuration is in effect.
  """

  @spec get_string(t, file_id) :: {:ok, String.t} | {:error, term}

  def get_string(sink, path) do
    GenServer.call(sink, {:get_string, path})
  end


  @doc """
  Returns whether the given file identifier has been written to.
  """

  @spec path_written?(t, file_id) :: boolean

  def path_written?(sink, path) do
    GenServer.call(sink, {:path_written, path})
  end


  @doc """
  Stops the sink process.
  """

  @spec stop(t) :: :ok

  def stop(sink) do
    GenServer.cast(sink, {:stop})
  end


  use GenServer

  defmodule State do
    @moduledoc false
    defstruct(
      dest_dir: nil,
      data: %{},
      allow_get: false,
      allow_overwrite: false
    )
  end


  def init(opts) do
    state = %State{
      dest_dir: Keyword.get(opts, :dest_dir, nil),
      allow_get: Keyword.get(opts, :allow_get, false),
      allow_overwrite: Keyword.get(opts, :allow_overwrite, false)
    }
    {:ok, state}
  end


  def handle_call({:write, path, str}, _from, state) do
    if not state.allow_overwrite and Map.has_key?(state.data, path) do
      {:reply, {:error, :file_exists}, state}
    else
      if state.dest_dir != nil do
        File.open(Path.expand(path, state.dest_dir), [:write], fn io ->
          IO.binwrite(io, str)
        end)
      end
      if not state.allow_get, do: str = nil
      state = %State{state | data: Map.put(state.data, path, str)}
      {:reply, :ok, state}
    end
  end

  def handle_call({:get_string, _path}, _from, %State{allow_get: nil} = state) do
    {:reply, {:error, :not_supported}, state}
  end

  def handle_call({:get_string, path}, _from, %State{data: data} = state) do
    result = case Map.fetch(data, path) do
      {:ok, str} -> {:ok, str}
      :error -> {:error, :not_found}
    end
    {:reply, result, state}
  end

  def handle_call({:path_written, path}, _from, %State{data: data} = state) do
    {:reply, Map.has_key?(data, path), state}
  end


  def handle_cast({:stop}, state) do
    {:stop, :normal, state}
  end

end
