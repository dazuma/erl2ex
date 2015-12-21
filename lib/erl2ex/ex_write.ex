
defmodule Erl2ex.ExWrite do

  defmodule Context do
    defstruct indent: 0,
              last_form: :start
  end


  def to_file(module, path, opts \\ []) do
    File.open!(path, [:write], fn io ->
      to_io(module, io, opts)
    end)
  end


  def to_io(ex_module, io, opts \\ []) do
    build_context(opts) |> write_module(ex_module, io)
    :ok
  end


  def to_str(module, opts \\ []) do
    {:ok, io} = StringIO.open("")
    to_io(module, io, opts)
    {:ok, {_, str}} = StringIO.close(io)
    str
  end


  defp build_context(_opts) do
    %Context{}
  end

  def increment_indent(context) do
    %Context{context | indent: context.indent + 1}
  end

  def decrement_indent(context) do
    %Context{context | indent: context.indent - 1}
  end


  defp write_module(context, %Erl2ex.ExModule{name: nil, forms: forms}, io) do
    context |> foreach(forms, io, &write_form/3)
  end

  defp write_module(context, %Erl2ex.ExModule{name: name, forms: forms, comments: comments}, io) do
    context
      |> write_comment_list(comments, :module_comments, io)
      |> skip_lines(:module_begin, io)
      |> write_string("defmodule :#{to_string(name)} do", io)
      |> increment_indent
      |> foreach(forms, io, &write_form/3)
      |> decrement_indent
      |> skip_lines(:module_end, io)
      |> write_string("end", io)
  end


  defp write_form(context, %Erl2ex.ExHeader{use_bitwise: use_bitwise, require_record: require_record}, io) do
    if use_bitwise or require_record do
      context = context |> skip_lines(:attr, io)
    end
    if use_bitwise do
      context = context |> write_string("use Bitwise, only_operators: true", io)
    end
    if require_record do
      context = context |> write_string("require Record", io)
    end
    context
  end

  defp write_form(context, %Erl2ex.ExFunc{comments: comments, clauses: [first_clause | remaining_clauses], public: public}, io) do
    context
      |> write_comment_list(comments, :func_header, io)
      |> write_func_clause(public, first_clause, :func_clause_first, io)
      |> foreach(remaining_clauses, fn (ctx, clause) ->
        write_func_clause(ctx, public, clause, :func_clause, io)
      end)
  end

  defp write_form(context, %Erl2ex.ExAttr{name: name, tracking_name: tracking_name, arg: arg, comments: comments}, io) do
    context
      |> skip_lines(:attr, io)
      |> foreach(comments, io, &write_string/3)
      |> write_raw_attr(name, tracking_name, arg, io)
  end

  defp write_form(context, %Erl2ex.ExDirective{directive: directive, name: name, comments: comments}, io) do
    context
      |> skip_lines(:attr, io)
      |> foreach(comments, io, &write_string/3)
      |> write_raw_directive(directive, name, io)
  end

  defp write_form(context, %Erl2ex.ExImport{module: module, funcs: funcs, comments: comments}, io) do
    context
      |> skip_lines(:attr, io)
      |> foreach(comments, io, &write_string/3)
      |> write_string("import #{Macro.to_string(module)}, only: #{Macro.to_string(funcs)}", io)
  end

  defp write_form(context, %Erl2ex.ExMacro{signature: signature, expr: expr, comments: comments}, io) do
    context
      |> write_comment_list(comments, :func_header, io)
      |> skip_lines(:func_clause_first, io)
      |> write_string("defmacrop #{Macro.to_string(signature)} do", io)
      |> increment_indent
      |> write_string("quote do", io)
      |> increment_indent
      |> write_string(Macro.to_string(expr), io)
      |> decrement_indent
      |> write_string("end", io)
      |> decrement_indent
      |> write_string("end", io)
  end


  defp write_raw_attr(context, name, tracking_name, arg, io) do
    context = context
      |> write_string("@#{name} #{Macro.to_string(arg)}", io)
    if tracking_name != nil do
      context = context
        |> write_string("@#{tracking_name} true", io)
    end
    context
  end


  defp write_raw_directive(context, :undef, tracking_name, io) do
    context
      |> write_string("@#{tracking_name} false", io)
  end

  defp write_raw_directive(context, :ifdef, tracking_name, io) do
    context
      |> write_string("if @#{tracking_name} do", io)
  end

  defp write_raw_directive(context, :ifndef, tracking_name, io) do
    context
      |> write_string("if not @#{tracking_name} do", io)
  end

  defp write_raw_directive(context, :else, nil, io) do
    context
      |> write_string("else", io)
  end

  defp write_raw_directive(context, :endif, nil, io) do
    context
      |> write_string("end", io)
  end


  defp write_comment_list(context, [], _form_type, _io), do: context
  defp write_comment_list(context, comments, form_type, io) do
    context
      |> skip_lines(form_type, io)
      |> foreach(comments, io, &write_string/3)
  end


  defp write_func_clause(context, public, clause, form_type, io) do
    decl = if public, do: "def", else: "defp"
    context
      |> skip_lines(form_type, io)
      |> foreach(clause.comments, io, &write_string/3)
      |> write_string("#{decl} #{Macro.to_string(clause.signature)} do", io)
      |> increment_indent
      |> foreach(clause.exprs, fn (ctx, expr) ->
        write_string(ctx, Macro.to_string(expr), io)
      end)
      |> decrement_indent
      |> write_string("end", io)
  end


  defp write_string(context, str, io) do
    indent = String.duplicate("  ", context.indent)
    String.split(str, "\n") |> Enum.each(fn line ->
      IO.puts(io, "#{indent}#{line}")
    end)
    context
  end


  defp foreach(context, list, io, func) do
    Enum.reduce(list, context, fn (elem, ctx) -> func.(ctx, elem, io) end)
  end

  defp foreach(context, list, func) do
    Enum.reduce(list, context, fn (elem, ctx) -> func.(ctx, elem) end)
  end


  defp skip_lines(context, cur_form, io) do
    lines = calc_skip_lines(context.last_form, cur_form)
    if lines > 0 do
      IO.puts(io, String.duplicate("\n", lines - 1))
    end
    %Context{context | last_form: cur_form}
  end

  defp calc_skip_lines(:start, _), do: 0
  defp calc_skip_lines(:module_comments, :module_begin), do: 1
  defp calc_skip_lines(:module_begin, _), do: 1
  defp calc_skip_lines(_, :module_end), do: 1
  defp calc_skip_lines(:func_header, :func_clause_first), do: 1
  defp calc_skip_lines(:func_clause_first, :func_clause), do: 1
  defp calc_skip_lines(:func_clause, :func_clause), do: 1
  defp calc_skip_lines(:attr, :attr), do: 1
  defp calc_skip_lines(_, _), do: 2


end
