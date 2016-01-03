
defmodule Erl2ex.Parse.ModuleBuilder do

  @moduledoc false


  alias Erl2ex.ErlAttr
  alias Erl2ex.ErlComment
  alias Erl2ex.ErlDefine
  alias Erl2ex.ErlDirective
  alias Erl2ex.ErlFunc
  alias Erl2ex.ErlImport
  alias Erl2ex.ErlModule
  alias Erl2ex.ErlRecord
  alias Erl2ex.ErlSpec
  alias Erl2ex.ErlType

  alias Erl2ex.Parse
  alias Erl2ex.Parse.Context


  def build(form_stream, context) do
    module = form_stream
      |> Enum.reduce(%ErlModule{},
        fn ({ast, comments}, module) -> add_form(module, ast, comments, context) end)
    if not context.reverse_forms do
      module = %ErlModule{module | forms: Enum.reverse(module.forms)}
    end
    module
  end


  defp add_form(module, {:function, _line, name, arity, clauses}, comments, _context) do
    func = %ErlFunc{name: name, arity: arity, clauses: clauses, comments: comments}
    %ErlModule{module | forms: [func | module.forms]}
  end

  defp add_form(module, {:attribute, _line, :module, arg}, comments, _context) do
    %ErlModule{module |
      name: arg,
      comments: module.comments ++ comments
    }
  end

  defp add_form(module, {:attribute, _line, :include, path}, _comments, context) do
    file_path = Context.find_file(context, path)
    opts = Context.build_opts_for_include(context)
    included_module = Parse.from_file(file_path, opts)
    comment1 = %ErlComment{comments: ["% Begin included file: #{List.to_string(path)}"]}
    comment2 = %ErlComment{comments: ["% End included file: #{List.to_string(path)}"]}
    %ErlModule{module |
      forms: [comment2 | included_module.forms] ++ [comment1 | module.forms]
    }
  end

  defp add_form(module, {:attribute, line, :include_lib, path}, _comments, context) do
    [lib_name | path_elems] = path
      |> List.to_string
      |> Path.relative
      |> Path.split
    rel_path = path_elems |> Path.join
    lib_atom = lib_name |> String.to_atom
    lib_path = lib_atom |> :code.lib_dir
    if is_tuple(lib_path) do
      raise CompileError,
        file: Context.cur_file_path_for_display(context),
        line: line,
        description: "Could not find library: #{lib_name}"
    end
    file_path =  List.to_string(lib_path) <> "/" <> rel_path
    opts = Context.build_opts_for_include(context)
    included_module = Parse.from_file(file_path, opts)
    comment1 = %ErlComment{comments: ["% Begin included file: #{rel_path} from library #{Atom.to_string(lib_atom)}"]}
    comment2 = %ErlComment{comments: ["% End included file: #{rel_path} from library #{Atom.to_string(lib_atom)}"]}
    %ErlModule{module |
      forms: [comment2 | included_module.forms] ++ [comment1 | module.forms]
    }
  end

  defp add_form(module, {:attribute, _line, :export, arg}, comments, _context) do
    %ErlModule{module |
      exports: module.exports ++ arg,
      comments: module.comments ++ comments
    }
  end

  defp add_form(module, {:attribute, _line, :export_type, arg}, _comments, _context) do
    %ErlModule{module |
      type_exports: module.type_exports ++ arg
    }
  end

  defp add_form(module, {:attribute, line, :import, {modname, funcs}}, comments, _context) do
    attribute = %ErlImport{line: line, module: modname, funcs: funcs, comments: comments}
    %ErlModule{module |
      imports: module.imports ++ funcs,
      forms: [attribute | module.forms]
    }
  end

  defp add_form(module, {:attribute, line, :type, {name, defn, params}}, comments, _context) do
    type = %ErlType{line: line, kind: :type, name: name, params: params, defn: defn, comments: comments}
    %ErlModule{module | forms: [type | module.forms]}
  end

  defp add_form(module, {:attribute, line, :opaque, {name, defn, params}}, comments, _context) do
    type = %ErlType{line: line, kind: :opaque, name: name, params: params, defn: defn, comments: comments}
    %ErlModule{module | forms: [type | module.forms]}
  end

  defp add_form(module, {:attribute, line, :spec, {{name, _}, clauses}}, comments, _context) do
    spec = %ErlSpec{line: line, name: name, clauses: clauses, comments: comments}
    %ErlModule{module | specs: [spec | module.specs]}
  end

  defp add_form(module, {:attribute, line, :spec, {{spec_mod, name, _}, clauses}}, comments, _context) do
    if spec_mod == module.name do
      spec = %ErlSpec{line: line, name: name, clauses: clauses, comments: comments}
      %ErlModule{module | specs: [spec | module.specs]}
    else
      module
    end
  end

  defp add_form(module, {:attribute, line, :callback, {{name, _}, clauses}}, comments, _context) do
    callback = %ErlSpec{line: line, name: name, clauses: clauses, comments: comments}
    %ErlModule{module | forms: [callback | module.forms]}
  end

  defp add_form(module, {:attribute, line, :record, {recname, fields}}, comments, _context) do
    record = %ErlRecord{line: line, name: recname, fields: fields, comments: comments}
    %ErlModule{module | forms: [record | module.forms]}
  end

  defp add_form(module, {:attribute, line, directive}, comments, _context) do
    form = %ErlDirective{line: line, directive: directive, comments: comments}
    %ErlModule{module | forms: [form | module.forms]}
  end

  defp add_form(module, {:attribute, line, directive, name}, comments, _context)
      when directive == :ifdef or directive == :ifndef or directive == :undef do
    form = %ErlDirective{line: line, directive: directive, name: macro_name(name), comments: comments}
    %ErlModule{module | forms: [form | module.forms]}
  end

  defp add_form(module, {:attribute, line, attr, arg}, comments, _context) do
    attribute = %ErlAttr{line: line, name: attr, arg: arg, comments: comments}
    %ErlModule{module | forms: [attribute | module.forms]}
  end

  defp add_form(module, {:define, line, macro, replacement}, comments, _context) do
    {name, args} = interpret_macro_expr(macro)
    define = %ErlDefine{
      line: line,
      name: name,
      args: args,
      replacement: replacement,
      comments: comments
    }
    %ErlModule{module | forms: [define | module.forms]}
  end

  defp add_form(_module, expr, _comments, context) do
    line = if is_tuple(expr) and tuple_size(expr) >= 3, do: elem(expr, 1), else: :unknown
    raise CompileError,
      file: Context.cur_file_path_for_display(context),
      line: line,
      description: "Unrecognized Erlang form ast: #{inspect(expr)}"
  end


  defp interpret_macro_expr({:call, _, name_expr, arg_exprs}) do
    name = macro_name(name_expr)
    args = arg_exprs |> Enum.map(fn {:var, _, n} -> n end)
    {name, args}
  end

  defp interpret_macro_expr(macro_expr) do
    name = macro_name(macro_expr)
    {name, nil}
  end


  defp macro_name({:var, _, name}), do: name
  defp macro_name({:atom, _, name}), do: name
  defp macro_name(name) when is_atom(name), do: name

end
