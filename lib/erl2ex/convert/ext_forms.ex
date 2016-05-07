# Conversion logic for extended (epp_dodger) AST forms.

defmodule Erl2ex.Convert.ExtForms do

  @moduledoc false


  alias Erl2ex.Pipeline.ExComment


  # A dispatching function that converts a form with a context. Returns a
  # tuple of a list (possibly empty) of ex_data forms, and an updated context.

  # This clause converts a comment form to an ExComment
  def conv_form(:comment, ext_form, context) do
    comments = ext_form
      |> :erl_syntax.comment_text
      |> Enum.map(&List.to_string/1)
      |> convert_comments
    ex_comment = %ExComment{comments: comments}
    {[ex_comment], context}
  end

  # This clause handles all other form types, and does not emit anything.
  def conv_form(_, _, context) do
    {[], context}
  end


  # Given a list of comment data, returns a list of Elixir comment strings.

  defp convert_comments(comments) do
    comments |> Enum.map(fn
      {:comment, _, str} -> str |> List.to_string |> convert_comment_str
      str when is_binary(str) -> convert_comment_str(str)
    end)
  end


  # Coverts an Erlang comment string to an Elixir comment string. i.e.
  # it changes the % delimiter to #.

  defp convert_comment_str(str) do
    Regex.replace(~r{^%+}, str, fn prefix -> String.replace(prefix, "%", "#") end)
  end

end
