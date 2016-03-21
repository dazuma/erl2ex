
defmodule Erl2ex.Results.Collector do

  alias Erl2ex.Results


  @type t :: pid()


  @spec start_link(list) :: t

  def start_link(opts \\ []) do
    {:ok, pid} = GenServer.start_link(__MODULE__, opts)
    pid
  end


  def write_success(results, input_path, output_path) do
    GenServer.call(results, {:success, input_path, output_path})
  end


  def write_error(results, input_path, error) do
    GenServer.call(results, {:error, input_path, error})
  end


  def get_file(results, path) do
    GenServer.call(results, {:get_file, path})
  end


  def get(results) do
    GenServer.call(results, {:get})
  end


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
