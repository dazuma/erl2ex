
defmodule Erl2ex.Codegen do

  @moduledoc false

  alias Erl2ex.ExAttr
  alias Erl2ex.ExCallback
  alias Erl2ex.ExComment
  alias Erl2ex.ExDirective
  alias Erl2ex.ExFunc
  alias Erl2ex.ExHeader
  alias Erl2ex.ExImport
  alias Erl2ex.ExMacro
  alias Erl2ex.ExModule
  alias Erl2ex.ExRecord
  alias Erl2ex.ExType


  def to_file(module, path, opts \\ []) do
    File.open!(path, [:write], fn io ->
      to_io(module, io, opts)
    end)
  end


  def to_io(ex_module, io, opts \\ []) do
    opts
      |> build_context
      |> write_module(ex_module, io)
    :ok
  end


  def to_str(module, opts \\ []) do
    {:ok, io} = StringIO.open("")
    to_io(module, io, opts)
    {:ok, {_, str}} = StringIO.close(io)
    str
  end


  defmodule Context do
    @moduledoc false
    defstruct indent: 0,
              last_form: :start,
              define_prefix: "",
              defines_from_config: nil
  end


  defp build_context(opts) do
    defines_from_config = Keyword.get(opts, :defines_from_config, nil)
    if is_binary(defines_from_config) do
      defines_from_config = String.to_atom(defines_from_config)
    end
    %Context{
      define_prefix: Keyword.get(opts, :define_prefix, "DEFINE_"),
      defines_from_config: defines_from_config
    }
  end

  def increment_indent(context) do
    %Context{context | indent: context.indent + 1}
  end

  def decrement_indent(context) do
    %Context{context | indent: context.indent - 1}
  end


  defp write_module(context, %ExModule{name: nil, forms: forms, file_comments: file_comments}, io) do
    context
      |> write_comment_list(file_comments, :structure_comments, io)
      |> foreach(forms, io, &write_form/3)
  end

  defp write_module(context, %ExModule{name: name, forms: forms, file_comments: file_comments, comments: comments}, io) do
    context
      |> write_comment_list(file_comments, :structure_comments, io)
      |> write_comment_list(comments, :module_comments, io)
      |> skip_lines(:module_begin, io)
      |> write_string("defmodule :#{to_string(name)} do", io)
      |> increment_indent
      |> foreach(forms, io, &write_form/3)
      |> decrement_indent
      |> skip_lines(:module_end, io)
      |> write_string("end", io)
  end


  defp write_form(context, header = %ExHeader{}, io) do
    if header.use_bitwise do
      context = context
        |> skip_lines(:attr, io)
        |> write_string("use Bitwise, only_operators: true", io)
    end
    context = context
      |> foreach(header.init_macros, fn(ctx, {name, defined_name}) ->
        ctx = ctx |> skip_lines(:attr, io)
        env_name = ctx.define_prefix <> to_string(name)
        get_env_syntax = if ctx.defines_from_config do
          "Application.get_env(#{inspect(ctx.defines_from_config)}, #{env_name |> String.to_atom |> inspect})"
        else
          "System.get_env(#{inspect(env_name)})"
        end
        ctx |> write_string("@#{defined_name} #{get_env_syntax} != nil", io)
      end)
    if not Enum.empty?(header.records) do
      context = context
        |> skip_lines(:attr, io)
        |> write_string("require Record", io)
    end
    if header.macro_dispatcher != nil do
      context = context
        |> skip_lines(:attr, io)
        |> write_string("defmacrop #{header.macro_dispatcher}(name, args), do:", io)
        |> increment_indent
        |> write_string("{Module.get_attribute(__MODULE__), name), [], args}", io)
        |> decrement_indent
        |> write_string("defmacrop #{header.macro_dispatcher}(name), do:", io)
        |> increment_indent
        |> write_string("{Module.get_attribute(__MODULE__), name), [], []}", io)
        |> decrement_indent
    end
    context
  end

  defp write_form(context, %ExComment{comments: comments}, io) do
    context
      |> write_comment_list(comments, :structure_comments, io)
  end

  defp write_form(context, %ExFunc{comments: comments, clauses: [first_clause | remaining_clauses], public: public, specs: specs}, io) do
    context
      |> write_comment_list(comments, :func_header, io)
      |> write_func_specs(specs, io)
      |> write_func_clause(public, first_clause, :func_clause_first, io)
      |> foreach(remaining_clauses, fn (ctx, clause) ->
        write_func_clause(ctx, public, clause, :func_clause, io)
      end)
  end

  defp write_form(context, %ExAttr{name: name, register: register, arg: arg, comments: comments}, io) do
    context
      |> skip_lines(:attr, io)
      |> foreach(comments, io, &write_string/3)
      |> write_raw_attr(name, register, arg, io)
  end

  defp write_form(context, %ExDirective{directive: directive, name: name, comments: comments}, io) do
    context
      |> skip_lines(:directive, io)
      |> foreach(comments, io, &write_string/3)
      |> write_raw_directive(directive, name, io)
  end

  defp write_form(context, %ExImport{module: module, funcs: funcs, comments: comments}, io) do
    context
      |> skip_lines(:attr, io)
      |> foreach(comments, io, &write_string/3)
      |> write_string("import #{Macro.to_string(module)}, only: #{Macro.to_string(funcs)}", io)
  end

  defp write_form(context, %ExRecord{tag: tag, macro: macro, fields: fields, comments: comments}, io) do
    context
      |> skip_lines(:attr, io)
      |> foreach(comments, io, &write_string/3)
      |> write_string("Record.defrecordp #{Macro.to_string(macro)}, #{Macro.to_string(tag)}, #{Macro.to_string(fields)}", io)
  end

  defp write_form(context, %ExType{kind: kind, signature: signature, defn: defn, comments: comments}, io) do
    context
      |> skip_lines(:attr, io)
      |> foreach(comments, io, &write_string/3)
      |> write_string("@#{kind} #{Macro.to_string(signature)} :: #{Macro.to_string(defn)}", io)
  end

  defp write_form(context, %ExCallback{specs: specs, comments: comments}, io) do
    context
      |> skip_lines(:attr, io)
      |> foreach(comments, io, &write_string/3)
      |> foreach(specs, fn(ctx, spec) ->
        write_string(ctx, "@callback #{Macro.to_string(spec)}", io)
      end)
  end

  defp write_form(
    context,
    %ExMacro{
      macro_name: macro_name,
      signature: signature,
      tracking_name: tracking_name,
      dispatch_name: dispatch_name,
      stringifications: stringifications,
      expr: expr,
      comments: comments
    },
    io)
  do
    context = context
      |> write_comment_list(comments, :func_header, io)
      |> skip_lines(:func_clause_first, io)
      |> write_string("defmacrop #{Macro.to_string(signature)} do", io)
      |> increment_indent
      |> foreach(stringifications, fn(ctx, {var, str}) ->
        write_string(ctx, "#{str} = Macro.to_string(quote do: unquote(#{var}))", io)
      end)
      |> write_string("quote do", io)
      |> increment_indent
      |> write_string(Macro.to_string(expr), io)
      |> decrement_indent
      |> write_string("end", io)
      |> decrement_indent
      |> write_string("end", io)
    if tracking_name != nil do
      context = context
        |> write_string("@#{tracking_name} true", io)
    end
    if dispatch_name != nil do
      context = context
        |> write_string("@#{dispatch_name} :#{macro_name}", io)
    end
    context
  end


  defp write_raw_attr(context, name, register, arg, io) do
    if register do
      context = context
        |> write_string("Module.register_attribute(__MODULE__, #{Macro.to_string(name)}, persist: true, accumulate: true)", io)
    end
    context
      |> write_string("@#{name} #{Macro.to_string(arg)}", io)
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


  defp write_func_specs(context, [], _io), do: context
  defp write_func_specs(context, specs, io) do
    context
      |> skip_lines(:func_specs, io)
      |> foreach(specs, fn(ctx, spec) ->
        write_string(ctx, "@spec #{Macro.to_string(spec)}", io)
      end)
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
    str
      |> String.split("\n")
      |> Enum.each(fn line ->
        IO.puts(io, "#{indent}#{line}")
      end)
    context
  end


  defp foreach(context, list, io, func) do
    Enum.reduce(list, context, fn (e, ctx) -> func.(ctx, e, io) end)
  end

  defp foreach(context, list, func) do
    Enum.reduce(list, context, fn (e, ctx) -> func.(ctx, e) end)
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
  defp calc_skip_lines(:func_header, :func_specs), do: 1
  defp calc_skip_lines(:func_header, :func_clause_first), do: 1
  defp calc_skip_lines(:func_specs, :func_clause_first), do: 1
  defp calc_skip_lines(:func_clause_first, :func_clause), do: 1
  defp calc_skip_lines(:func_clause, :func_clause), do: 1
  defp calc_skip_lines(:attr, :attr), do: 1
  defp calc_skip_lines(_, _), do: 2


end
