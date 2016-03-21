
defmodule Erl2ex.Results.Collector do

  @moduledoc """
  Erl2ex.Results.Collector is a process that accumulates results of a
  conversion run.
  """


  alias Erl2ex.Results


  @typedoc """
  The ProcessID of a results collector process.
  """

  @type t :: pid()


  @typedoc """
  A file identifier, which may be a filesystem path or a symbolic id.
  """

  @type file_id :: Path.t | atom


  @doc """
  Starts a result collector and returns its PID.
  """

  @spec start_link(list) :: t

  def start_link(opts \\ []) do
    {:ok, pid} = GenServer.start_link(__MODULE__, opts)
    pid
  end


  @doc """
  Record that a conversion was successful for the given input and output paths.
  """

  @spec put_success(t, file_id, file_id) :: :ok | {:error, term}

  def put_success(results, input_path, output_path) do
    GenServer.call(results, {:success, input_path, output_path})
  end


  @doc """
  Record that a conversion was unsuccessful for the given input path.
  """

  @spec put_error(t, file_id, %CompileError{}) :: :ok | {:error, term}

  def put_error(results, input_path, error) do
    GenServer.call(results, {:error, input_path, error})
  end


  @doc """
  Returns the results for the given input path.
  """

  @spec get_file(t, file_id) :: {:ok, Results.File.t} | {:error, term}

  def get_file(results, path) do
    GenServer.call(results, {:get_file, path})
  end


  @doc """
  Returns the results for the entire conversion so far.
  """

  @spec get(t) :: Results.t

  def get(results) do
    GenServer.call(results, {:get})
  end


  @doc """
  Stops the collector process.
  """

  @spec stop(t) :: :ok

  def stop(results) do
    GenServer.cast(results, {:stop})
  end


  use GenServer

  defmodule State do
    @moduledoc false
    defstruct(
      data: %{},
      allow_overwrite: false
    )
  end


  def init(opts) do
    state = %State{
      allow_overwrite: Keyword.get(opts, :allow_overwrite, false)
    }
    {:ok, state}
  end


  def handle_call({:success, input_path, output_path}, _from, state) do
    if not state.allow_overwrite and Map.has_key?(state.data, input_path) do
      {:reply, {:error, :file_exists}, state}
    else
      file = %Results.File{
        input_path: input_path,
        output_path: output_path
      }
      state = %State{state | data: Map.put(state.data, input_path, file)}
      {:reply, :ok, state}
    end
  end

  def handle_call({:error, input_path, error}, _from, state) do
    if not state.allow_overwrite and Map.has_key?(state.data, input_path) do
      {:reply, {:error, :file_exists}, state}
    else
      file = %Results.File{
        input_path: input_path,
        error: error
      }
      state = %State{state | data: Map.put(state.data, input_path, file)}
      {:reply, :ok, state}
    end
  end

  def handle_call({:get_file, input_path}, _from, %State{data: data} = state) do
    reply = case Map.fetch(data, input_path) do
      {:ok, file} -> {:ok, file}
      :error -> {:error, :not_found}
    end
    {:reply, reply, state}
  end

  def handle_call({:get}, _from, %State{data: data} = state) do
    {:reply, %Results{files: Map.values(data)}, state}
  end


  def handle_cast({:stop}, state) do
    {:stop, :normal, state}
  end

end
