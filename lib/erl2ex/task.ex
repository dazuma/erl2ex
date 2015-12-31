# Mix task for erl2ex

defmodule Mix.Tasks.Erl2ex do

  @moduledoc Erl2ex.Cli.usage_text("mix erl2ex")

  @shortdoc "Transpiles Erlang source to Elixir"

  use Mix.Task


  def run(args) do
    Erl2ex.Cli.main(args)
  end

end
