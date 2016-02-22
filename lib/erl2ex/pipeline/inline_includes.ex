
defmodule Erl2ex.Pipeline.InlineIncludes do

  @moduledoc false

  alias Erl2ex.Source

  alias Erl2ex.Pipeline.ErlSyntax
  alias Erl2ex.Pipeline.Parse


  def process(forms, source, main_source_path) do
    forms |> Enum.flat_map(&(handle_form(&1, source, main_source_path)))
  end


  defp handle_form({_erl_ast, form_node} = form, source, main_source_path) do
    ErlSyntax.on_static_attribute(form_node, [form], fn name, arg_nodes ->
      ErlSyntax.on_trees1(arg_nodes, [form], fn arg_node ->
        ErlSyntax.on_string(arg_node, [form], fn path ->
          path = Regex.replace(~r/^\$(\w+)/, path, fn (match, env) ->
            case System.get_env(env) do
              nil -> match
              val -> val
            end
          end)
          case name do
            :include ->
              source_dir = if main_source_path == nil, do: nil, else: Path.dirname(main_source_path)
              {include_str, include_path} = Source.read_include(source, path, source_dir)
              do_include(include_str, include_path, path, source, main_source_path)
            :include_lib ->
              [lib_name | path_elems] = path |> Path.relative |> Path.split
              rel_path = Path.join(path_elems)
              lib_atom = String.to_atom(lib_name)
              {include_str, include_path} = Source.read_lib_include(source, lib_atom, rel_path)
              display_path = "#{rel_path} from library #{lib_name}"
              do_include(include_str, include_path, display_path, source, main_source_path)
            _ ->
              [form]
          end
        end)
      end)
    end)
  end


  defp do_include(include_str, include_path, display_path, source, main_source_path) do
    include_forms = include_str
      |> Parse.string(cur_file_path: include_path)
      |> process(source, main_source_path)
    pre_comment = :erl_syntax.comment(['% Begin included file: #{display_path}'])
    post_comment = :erl_syntax.comment(['% End included file: #{display_path}'])
    [{nil, pre_comment} | include_forms] ++ [{nil, post_comment}]
  end

end
