
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

    @type t :: %__MODULE__{
      input_path: Path.t | nil,
      output_path: Path.t | nil,
      error: %CompileError{} | nil
    }
  end


  defstruct(
    files: []
  )


  @type t :: %__MODULE__{
    files: [Results.File.t]
  }


  @spec success?(Results.t | Results.File.t) :: boolean

  def success?(%Results{files: files}), do:
    not Enum.any?(files, &get_error/1)
  def success?(%Results.File{error: nil}), do: true
  def success?(%Results.File{}), do: false


  @spec get_error(Results.t | Results.File.t) :: %CompileError{} | nil

  def get_error(%Results{files: files}), do:
    Enum.find_value(files, &get_error/1)
  def get_error(%Results.File{error: err}), do: err


  @spec throw_error(a) :: a when a: Results.t

  def throw_error(results) do
    case get_error(results) do
      nil -> results
      err -> throw(err)
    end
  end


end
