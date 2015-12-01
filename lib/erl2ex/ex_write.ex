
defmodule Erl2ex.ExWrite do

  def to_file(module, path, opts \\ []) do
    File.open!(path, [:write], fn io ->
      to_io(module, io, opts)
      :ok
    end)
  end


  def to_io(module, io, opts \\ []) do
    module.comments |> Enum.each(&(write_string(io, &1, opts)))
    write_string(io, "defmodule :#{to_string(module.name)} do", opts)
    inner_opts = increment_indent(opts)
    module.forms |> Enum.each(&(write_form(io, &1, inner_opts)))
    write_string(io, "end", opts)
    io
  end


  def to_str(module, opts \\ []) do
    {:ok, io} = StringIO.open("")
    to_io(module, io, opts)
    {:ok, {_, str}} = StringIO.close(io)
    str
  end


  defp write_form(io, func = %Erl2ex.ExFunc{}, opts) do
    write_string(io, "", opts)
    func.comments |> Enum.each(&(write_string(io, &1, opts)))
    func.clauses |> Enum.each(&(write_clause(io, func, &1, opts)))
  end

  defp write_form(io, attr = %Erl2ex.ExAttr{}, opts) do
    attr.comments |> Enum.each(&(write_string(io, &1, opts)))
    write_string(io, "@#{attr.name} #{Macro.to_string(attr.arg)}", opts)
    write_string(io, "", opts)
  end


  defp write_clause(io, func, clause, opts) do
    clause.comments |> Enum.each(&(write_string(io, &1, opts)))
    write_string(io, "#{func_declaration(func)}#{func_args(clause)}#{func_guard(clause)} do", opts)
    inner_opts = increment_indent(opts)
    clause.exprs |> Enum.each(fn expr ->
      write_string(io, Macro.to_string(expr), inner_opts)
    end)
    write_string(io, "end", opts)
    write_string(io, "", opts)
  end


  defp func_declaration(%Erl2ex.ExFunc{public: true, name: name}), do: "def #{name}"
  defp func_declaration(%Erl2ex.ExFunc{public: false, name: name}), do: "defp #{name}"

  defp func_args(clause) do
    args = clause.args
      |> Enum.map(&Macro.to_string/1)
      |> Enum.join(", ")
    "(#{args})"
  end

  defp func_guard(%Erl2ex.ExClause{guard: nil}), do: ""
  defp func_guard(%Erl2ex.ExClause{guard: guard}), do: " when #{Macro.to_string(guard)}"


  defp write_string(io, str, opts) do
    indent = Keyword.get(opts, :indent, "")
    IO.puts(io, String.rstrip("#{indent}#{str}"))
  end


  @indent "  "

  defp increment_indent(opts) do
    Keyword.update(opts, :indent, @indent, &("#{&1}#{@indent}"))
  end

end
