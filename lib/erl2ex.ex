defmodule Erl2ex do

  require Logger


  def convert_dir(source_dir, dest_dir \\ nil, opts \\ []) do
    if dest_dir == nil do
      dest_dir = source_dir
    end
    Path.wildcard("#{source_dir}/**/*.erl")
      |> Enum.each(fn source_path ->
        dest_path = Path.relative_to(source_path, source_dir)
        dest_path = Path.join(dest_dir, dest_path)
        dest_path = "#{Path.rootname(dest_path)}.ex"
        convert_file(source_path, dest_path, opts)
      end)
  end


  def convert_file(source_path, dest_path \\ nil, opts \\ []) do
    if dest_path == nil do
      dest_path = "#{Path.rootname(source_path)}.ex"
    end
    Erl2ex.ErlParse.from_file(source_path, opts)
      |> Erl2ex.Convert.module(opts)
      |> Erl2ex.ExWrite.to_file(dest_path, opts)
    Logger.info("Converted #{source_path} -> #{dest_path}")
  end


  def convert_str(source, opts \\ []) do
    Erl2ex.ErlParse.from_str(source, opts)
      |> Erl2ex.Convert.module(opts)
      |> Erl2ex.ExWrite.to_str(opts)
  end

end
