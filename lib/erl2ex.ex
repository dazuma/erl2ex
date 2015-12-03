defmodule Erl2ex do

  def convert_file(source_path, dest_path, opts \\ []) do
    Erl2ex.ErlParse.from_file(source_path, opts)
      |> Erl2ex.Convert.module(opts)
      |> Erl2ex.ExWrite.to_file(dest_path, opts)
  end


  def convert_str(source, opts \\ []) do
    Erl2ex.ErlParse.from_str(source, opts)
      |> Erl2ex.Convert.module(opts)
      |> Erl2ex.ExWrite.to_str(opts)
  end

end
