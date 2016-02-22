
defmodule Erl2ex.Convert.ExtForms do

  @moduledoc false


  alias Erl2ex.Pipeline.ExComment


  def conv_form(:comment, ext_form, context) do
    comments = ext_form
      |> :erl_syntax.comment_text
      |> Enum.map(&List.to_string/1)
      |> convert_comments
    ex_comment = %ExComment{comments: comments}
    {[ex_comment], context}
  end

  def conv_form(_, _, context) do
    {[], context}
  end


  defp convert_comments(comments) do
    comments |> Enum.map(fn
      {:comment, _, str} -> str |> List.to_string |> convert_comment_str
      str when is_binary(str) -> convert_comment_str(str)
    end)
  end

  defp convert_comment_str(str) do
    Regex.replace(~r{^%+}, str, fn prefix -> String.replace(prefix, "%", "#") end)
  end

end
