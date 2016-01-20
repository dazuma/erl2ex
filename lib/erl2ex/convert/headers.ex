
defmodule Erl2ex.Convert.Headers do

  @moduledoc false

  alias Erl2ex.ExAttr
  alias Erl2ex.ExClause
  alias Erl2ex.ExFunc
  alias Erl2ex.ExHeader
  alias Erl2ex.ExMacro

  alias Erl2ex.Analyze


  def build_header(analysis, forms) do
    header = forms
      |> Enum.reduce(%ExHeader{}, &header_check_form/2)
    %ExHeader{header |
      records: Analyze.map_records(analysis, fn(name, fields) -> {name, fields} end),
      init_macros: Analyze.macros_that_need_init(analysis),
      macro_dispatcher: Analyze.macro_dispatcher_name(analysis),
      record_size_macro: Analyze.record_size_macro(analysis),
      record_index_macro: Analyze.record_index_macro(analysis)
    }
  end


  defp header_check_form(%ExFunc{clauses: clauses}, header), do:
    clauses |> Enum.reduce(header, &header_check_clause/2)
  defp header_check_form(%ExMacro{expr: expr}, header), do:
    header_check_expr(expr, header)
  defp header_check_form(%ExAttr{arg: arg}, header), do:
    header_check_expr(arg, header)
  defp header_check_form(_form, header), do: header


  defp header_check_clause(%ExClause{exprs: exprs}, header), do:
    exprs |> Enum.reduce(header, &header_check_expr/2)


  defp header_check_expr(expr, header) when is_tuple(expr) and tuple_size(expr) == 2, do:
    header_check_expr(elem(expr, 1), header)

  defp header_check_expr(expr, header) when is_tuple(expr) and tuple_size(expr) >= 3 do
    imported = expr |> elem(1) |> Keyword.get(:import, nil)
    if imported == Bitwise do
      header = %ExHeader{header | use_bitwise: true}
    end
    expr
      |> Tuple.to_list
      |> Enum.reduce(header, &header_check_expr/2)
  end

  defp header_check_expr(expr, header) when is_list(expr), do:
    expr |> Enum.reduce(header, &header_check_expr/2)

  defp header_check_expr(_expr, header), do: header

end
