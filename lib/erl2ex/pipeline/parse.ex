# This is the first phase of the pipeline. It parses the input file string
# using both the standard Erlang parser (erlparse) and the alternate
# generalized parser (epp_dodger). Both parsers have their strengths and
# weaknesses, and we expect to use data from both sources.

defmodule Erl2ex.Pipeline.Parse do

  @moduledoc false


  # Takes a string as input, and returns the forms in the file as a list
  # of {erlparse_form, epp_dodger_form} tuples.
  #
  # Currently, an error from either parser will cause the entire parse to fail;
  # however, later we expect to relax that behavior because some valid Erlang
  # code is expected to fail erlparse (due to preprocessor syntax). At that
  # time, we will return nil for failed erlparse forms.

  def string(str, opts \\ []) do
    charlist = generate_charlist(str)
    erl_forms = parse_erl_forms(charlist, opts)
    ext_forms = parse_ext_forms(charlist, opts)
    Enum.zip(erl_forms, ext_forms)
  end


  # Converts the given string to charlist (expected by Erlang's parsers) and
  # make sure it ends with a newline (also expected by Erlang's parsers).

  defp generate_charlist(str) do
    if not String.ends_with?(str, "\n") do
      str = str <> "\n"
    end
    String.to_char_list(str)
  end


  #### The erl_parse parser ####


  # Runs erl_parse on the given charlist, returning a list of forms.

  defp parse_erl_forms(charlist, opts) do
    charlist
      |> generate_token_group_stream
      |> Stream.map(&preprocess_tokens_for_erl/1)
      |> Stream.map(&(parse_erl_form(&1, opts)))
      |> Enum.to_list
  end


  # Given a charlist, runs erl_scan, grouping tokens into forms, and returns a
  # stream of those token lists (one list per form).

  defp generate_token_group_stream(charlist) do
    {charlist, 1}
      |> Stream.unfold(fn {ch, pos} ->
        case :erl_scan.tokens([], ch, pos, [:return_comments]) do
          {:done, {:ok, tokens, npos}, nch} -> {tokens, {nch, npos}}
          _ -> nil
        end
      end)
  end


  # Preprocesses tokens for erl_parse. Does the following mapping to simulate
  # the preprocessor:
  #
  # * Two "?"s followed by an atom or variable is interpreted as a stringify
  #   operator and turned into the variable "??#{name}". This is otherwise
  #   an illegal variable name, so we can detect it reliably during conversion.
  # * A single "?" followed by an atom or variable is interpreted as a macro
  #   invocation and turned into the variable "?#{name}". This is otherwise
  #   an illegal variable name, so we can detect it reliably during conversion.
  # * Comments are stripped because erlparse doesn't like them.

  defp preprocess_tokens_for_erl(form_tokens), do:
    preprocess_tokens_for_erl(form_tokens, [])

  defp preprocess_tokens_for_erl([], result), do: Enum.reverse(result)
  defp preprocess_tokens_for_erl([{:"?", _}, {:"?", _}, {:atom, line, name} | tail], result), do:
    preprocess_tokens_for_erl(tail, [{:var, line, :"??#{name}"} | result])
  defp preprocess_tokens_for_erl([{:"?", _}, {:"?", _}, {:var, line, name} | tail], result), do:
    preprocess_tokens_for_erl(tail, [{:var, line, :"??#{name}"} | result])
  defp preprocess_tokens_for_erl([{:"?", _}, {:atom, line, name} | tail], result), do:
    preprocess_tokens_for_erl(tail, [{:var, line, :"?#{name}"} | result])
  defp preprocess_tokens_for_erl([{:"?", _}, {:var, line, name} | tail], result), do:
    preprocess_tokens_for_erl(tail, [{:var, line, :"?#{name}"} | result])
  defp preprocess_tokens_for_erl([{:comment, _, _} | tail], result), do:
    preprocess_tokens_for_erl(tail, result)
  defp preprocess_tokens_for_erl([tok | tail], result), do:
    preprocess_tokens_for_erl(tail, [tok | result])


  # Parses a single form for erl_parse. We detect certain preprocessor cases up
  # front because erl_parse itself doesn't like the format.

  # This clause handles define directives.
  defp parse_erl_form([{:-, line} | defn_tokens = [{:atom, _, :define} | _]], opts) do
    parse_erl_define(line, defn_tokens, opts)
  end

  # This clause handles other directives that take an argument (like ifdef) and
  # creates a pseudo attribute node.
  defp parse_erl_form([{:-, line} | defn_tokens = [{:atom, _, directive} | _]], opts)
  when directive == :ifdef or directive == :ifndef or directive == :undef do
    [{:call, _, {:atom, _, ^directive}, [value]}] =
      defn_tokens |> :erl_parse.parse_exprs |> handle_erl_parse_result(opts)
    {:attribute, line, directive, value}
  end

  # This clause handles other directives that take no argument (like endif) and
  # creates a pseudo attribute node.
  defp parse_erl_form([{:-, line}, {:atom, _, directive}, {:dot, _}], _opts) do
    {:attribute, line, directive}
  end

  # This clause handles any other form by passing it to erl_parse.
  defp parse_erl_form(form_tokens, opts) do
    form_tokens |> :erl_parse.parse_form |> handle_erl_parse_result(opts)
  end


  # Parser for define directives. We have to handle some of the parsing
  # manually because a define may define a guard or a multi-expression
  # replacement that has separate clauses separated by commas or semicolons,
  # which erl_parser doesn't like in an attribute.

  # Cases with no arguments.
  defp parse_erl_define(line, [{:atom, _, :define}, {:"(", _}, name_token, {:",", dot_line} | replacement_tokens], opts) do
    parse_erl_define(line, [name_token, {:dot, dot_line}], replacement_tokens, opts)
  end

  # Cases with arguments.
  defp parse_erl_define(line, [{:atom, _, :define}, {:"(", _} | remaining_tokens = [_, {:"(", _} | _]], opts) do
    close_paren_index = remaining_tokens
      |> Enum.find_index(fn
        {:")", _} -> true
        _ -> false
      end)
    {macro_tokens, [{:",", dot_line} | replacement_tokens]} = Enum.split(remaining_tokens, close_paren_index + 1)
    parse_erl_define(line, macro_tokens ++ [{:dot, dot_line}], replacement_tokens, opts)
  end


  # The core of define parsing. Parse the macro name and replacement separately.
  # If parsing of the replacement fails, it's probably because there are
  # commas or semicolons and it should be treated as a guard. To parse that
  # case, we pretend it is a guard, and embed it in a fake function AST.
  # Pass that AST to erl_parse, and then extract the parsed guards.

  defp parse_erl_define(line, macro_tokens, replacement_tokens, opts) do
    macro_expr = macro_tokens
      |> :erl_parse.parse_exprs
      |> handle_erl_parse_result(opts)
      |> hd
    replacement_tokens = replacement_tokens |> List.delete_at(-2)
    replacement_exprs = case :erl_parse.parse_exprs(replacement_tokens) do
      {:ok, asts} -> [asts]
      {:error, _} ->
        {guard_tokens, [{:dot, dot_line}]} = Enum.split(replacement_tokens, -1)
        temp_form_tokens = [{:atom, 1, :foo}, {:"(", 1}, {:")", 1}, {:when, 1}] ++
            guard_tokens ++
            [{:"->", dot_line}, {:atom, dot_line, :ok}, {:dot, dot_line}]
        {:ok, {:function, _, :foo, 0, [{:clause, _, [], guards, _}]}} = :erl_parse.parse_form(temp_form_tokens)
        guards
    end
    {:define, line, macro_expr, replacement_exprs}
  end


  # Handle results of erl_parse, raising an appropriate CompileError on error.

  defp handle_erl_parse_result({:ok, ast}, _opts), do: ast

  defp handle_erl_parse_result({:error, {line, :erl_parse, messages = [h | _]}}, opts) when is_list(h) do
    raise CompileError,
      file: Keyword.get(opts, :cur_file_path, "(unknown source file)"),
      line: line,
      description: Enum.join(messages)
  end

  defp handle_erl_parse_result({:error, {line, :erl_parse, messages}}, opts) do
    raise CompileError,
      file: Keyword.get(opts, :cur_file_path, "(unknown source file)"),
      line: line,
      description: inspect(messages)
  end

  defp handle_erl_parse_result(info, opts) do
    raise CompileError,
      file: Keyword.get(opts, :cur_file_path, "(unknown source file)"),
      line: :unknown,
      description: "Unknown error: #{inspect(info)}"
  end


  #### The epp_dodger parser ####


  # Entry point for this parser. Takes a charlist and returns a list of trees.

  defp parse_ext_forms(charlist, opts) do
    comments = :erl_comment_scan.string(charlist)
    {:ok, io} = charlist
      |> preprocess_charlist_for_ext
      |> List.to_string
      |> StringIO.open
    case :epp_dodger.parse(io) do
      {:ok, forms} ->
        reconcile_comments(forms, comments)
      {:error, {line, _, desc}} ->
        raise CompileError,
          file: Keyword.get(opts, :cur_file_path, "(unknown source file)"),
          line: line,
          description: desc
    end
  end


  # The epp_dodger parser doesn't like the "??" stringification operator.
  # We preprocess the inputs by converting those to a single "?" operator
  # followed by an atom beginning with "??". This form is the recognized
  # specially by the converter as a pseudo-macro call.

  defp preprocess_charlist_for_ext(charlist) do
    {charlist, 1}
      |> Stream.unfold(fn {ch, pos} ->
        case :erl_scan.tokens([], ch, pos) do
          {:done, {:ok, tokens, npos}, nch} -> {tokens, {nch, npos}}
          _ -> nil
        end
      end)
      |> Enum.to_list
      |> List.flatten
      |> preprocess_tokens_for_ext([])
      |> unscan
  end

  defp preprocess_tokens_for_ext([], result), do: Enum.reverse(result)
  defp preprocess_tokens_for_ext([{:"?", _}, {:"?", _}, {type, line, name} | tail], result)
  when type == :atom or type == :var do
    preprocess_tokens_for_ext(tail, [{:atom, line, :"??#{name}"}, {:"?", line} | result])
  end
  defp preprocess_tokens_for_ext([tok | tail], result), do:
    preprocess_tokens_for_ext(tail, [tok | result])


  # In order to do the above preprocessing, we have to scan the input,
  # preprocess, and then unscan back into a charlist. It turns out that while
  # epp_dodger.tokens_to_string could do this, it doesn't preserve newlines
  # correctly, which is necessary to reconstruct the correct line numbers for
  # error messages. So I lifted the below implementation from epp_dodger and
  # modified it to preserve newlines.

  defp unscan(list) do
    list
      |> Enum.flat_map_reduce(1, fn tok, last_line ->
        line = elem(tok, 1)
        {generate_newlines(line - last_line) ++ unscan_token(tok), line}
      end)
      |> elem(0)
  end

  defp unscan_token({:atom, _, a}), do: :io_lib.write_atom(a) ++ ' '
  defp unscan_token({:string, _, s}), do: :io_lib.write_string(s) ++ ' '
  defp unscan_token({:char, _, c}), do: :io_lib.write_char(c) ++ ' '
  defp unscan_token({:float, _, f}), do: :erlang.float_to_list(f) ++ ' '
  defp unscan_token({:integer, _, n}), do: :erlang.integer_to_list(n) ++ ' '
  defp unscan_token({:var, _, a}), do: :erlang.atom_to_list(a) ++ ' '
  defp unscan_token({:dot, _}), do: '. '
  defp unscan_token({:., _}), do: '.'
  defp unscan_token({a, _}), do: :erlang.atom_to_list(a) ++ ' '

  defp generate_newlines(0), do: []
  defp generate_newlines(i), do: [?\n | generate_newlines(i - 1)]


  # Combine comments back into the given forms and return the modified forms.
  # Ideally, this would invoke erl_recomment, but that doesn't seem to be
  # working correctly. Need to investigate why.

  defp reconcile_comments(forms, _comments) do
    # TODO
    forms
  end

end
