
defmodule Erl2ex.Cli do

  def main(argv) do
    {options, [in_path, out_path], _errors} =
      OptionParser.parse(argv,
        strict: [
          verbose: :boolean
        ],
        aliases: [v: :verbose]
      )
    Erl2ex.convert_file(in_path, out_path, options)
  end

end
