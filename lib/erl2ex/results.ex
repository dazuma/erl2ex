
defmodule Erl2ex.Results do

  @moduledoc """
  Erl2ex.Results defines the structure of result data returned from most
  functions in the Erl2ex module.
  """


  alias Erl2ex.Results


  defmodule File do

    @moduledoc """
    Erl2ex.Results.File defines the result data structure for a particular file.
    """

    defstruct(
      input_path: nil,
      output_path: nil,
      error: nil
    )


    @typedoc """
    The conversion results of a single file.

    *   `input_path` is the path to the input Erlang file, or nil if the input
        is a string
    *   `output_path` is the path to the output Elixir file, or nil if the
        output is a string.
    *   `error` is the CompileError if a fatal error happened, or nil if the
        conversion was successful.
    """

    @type t :: %__MODULE__{
      input_path: Path.t | nil,
      output_path: Path.t | nil,
      error: %CompileError{} | nil
    }
  end


  defstruct(
    files: []
  )


  @typedoc """
  Overall results for an entire conversion job of one or more files.
  """

  @type t :: %__MODULE__{
    files: [Results.File.t]
  }


  @doc """
  Returns true if the entire conversion was successful, meaning no file
  resulted in an error.
  """

  @spec success?(Results.t | Results.File.t) :: boolean

  def success?(%Results{files: files}), do:
    not Enum.any?(files, &get_error/1)
  def success?(%Results.File{error: nil}), do: true
  def success?(%Results.File{}), do: false


  @doc """
  Returns the error that caused a conversion to fail, or nil if the conversion
  was successful. If more than one fatal error was detected, one error is
  returned but it is undefined which one is chosen.
  """

  @spec get_error(Results.t | Results.File.t) :: %CompileError{} | nil

  def get_error(%Results{files: files}), do:
    Enum.find_value(files, &get_error/1)
  def get_error(%Results.File{error: err}), do: err


  @doc """
  If the conversion failed, throw the error that caused the failure. Otherwise
  return the results.
  """

  @spec throw_error(a) :: a when a: Results.t

  def throw_error(results) do
    case get_error(results) do
      nil -> results
      err -> throw(err)
    end
  end


end
