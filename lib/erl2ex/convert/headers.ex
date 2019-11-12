# Logic to determine what should appear in the "header" of the Elixir module.

defmodule Erl2ex.Convert.Headers do
  @moduledoc false

  alias Erl2ex.Pipeline.ExAttr
  alias Erl2ex.Pipeline.ExClause
  alias Erl2ex.Pipeline.ExFunc
  alias Erl2ex.Pipeline.ExHeader
  alias Erl2ex.Pipeline.ExMacro

  alias Erl2ex.Pipeline.ModuleData

  # Builds an ExHeader structure specifying what should go in the Elixir module
  # header.

  def build_header(module_data, forms) do
    header =
      forms
      |> Enum.reduce(%ExHeader{}, &header_check_form/2)

    %ExHeader{
      header
      | records: ModuleData.map_records(module_data, fn name, fields -> {name, fields} end),
        has_is_record: module_data.has_is_record,
        init_macros: ModuleData.macros_that_need_init(module_data),
        macro_dispatcher: ModuleData.macro_dispatcher_name(module_data),
        record_size_macro: ModuleData.record_size_macro(module_data),
        record_index_macro: ModuleData.record_index_macro(module_data)
    }
  end

  # Dispatcher called during reduction over forms.

  defp header_check_form(%ExFunc{clauses: clauses}, header), do: clauses |> Enum.reduce(header, &header_check_clause/2)
  defp header_check_form(%ExMacro{expr: expr}, header), do: header_check_expr(expr, header)
  defp header_check_form(%ExAttr{arg: arg}, header), do: header_check_expr(arg, header)
  defp header_check_form(_form, header), do: header

  defp header_check_clause(%ExClause{exprs: exprs}, header), do: exprs |> Enum.reduce(header, &header_check_expr/2)

  # Searches expressions looking for uses of Bitwise operator, to determine
  # whether we need to use Bitwise.

  defp header_check_expr(expr, header) when is_tuple(expr) and tuple_size(expr) == 2,
    do: header_check_expr(elem(expr, 1), header)

  defp header_check_expr(expr, header) when is_tuple(expr) and tuple_size(expr) >= 3 do
    imported = expr |> elem(1) |> Keyword.get(:import, nil)

    header =
      if imported == Bitwise do
        %ExHeader{header | use_bitwise: true}
      else
        header
      end

    expr
    |> Tuple.to_list()
    |> Enum.reduce(header, &header_check_expr/2)
  end

  defp header_check_expr(expr, header) when is_list(expr), do: expr |> Enum.reduce(header, &header_check_expr/2)

  defp header_check_expr(_expr, header), do: header
end
