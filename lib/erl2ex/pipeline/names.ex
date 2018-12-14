# This module knows about things like reserved words and other special names,
# and what names are allowed in what contexts.

defmodule Erl2ex.Pipeline.Names do

  @moduledoc false


  # These are not allowed as names of functions or variables.
  # The converter will attempt to rename things that use one of these names.
  # If an exported function uses one of these names, it will require special
  # handling in both definition and calling.

  @elixir_reserved_words [
    :after,
    :and,
    :catch,
    :do,
    :else,
    :end,
    :false,
    :fn,
    :nil,
    :not,
    :or,
    :rescue,
    :true,
    :unquote,
    :unquote_splicing,
    :when,
    :__CALLER__,
    :__DIR__,
    :__ENV__,
    :__MODULE__,
    :__aliases__,
    :__block__
  ] |> Enum.into(MapSet.new)


  # These are not allowed as qualified function names because Elixir's parser
  # treats them specially. Calling functions with these names requires using
  # Kernel.apply.

  @elixir_uncallable_functions [
    :unquote,
    :unquote_splicing
  ] |> Enum.into(MapSet.new)


  # This is a map of Erlang BIFs to equivalent Elixir functions.

  @bif_map %{
    abs: :abs,
    apply: :apply,
    bit_size: :bit_size,
    byte_size: :byte_size,
    hd: :hd,
    is_atom: :is_atom,
    is_binary: :is_binary,
    is_bitstring: :is_bitstring,
    is_boolean: :is_boolean,
    is_float: :is_float,
    is_function: :is_function,
    is_integer: :is_integer,
    is_list: :is_list,
    is_map: :is_map,
    is_number: :is_number,
    is_pid: :is_pid,
    is_port: :is_port,
    is_record: {Record, :is_record},
    is_reference: :is_reference,
    is_tuple: :is_tuple,
    length: :length,
    make_ref: :make_ref,
    map_size: :map_size,
    max: :max,
    min: :min,
    node: :node,
    round: :round,
    self: :self,
    throw: :throw,
    tl: :tl,
    trunc: :trunc,
    tuple_size: :tuple_size
  }


  # These names are allowed as names of functions or variables, but clash with
  # Elixir special forms.
  # The converter will allow variables with these names, but will attempt to
  # rename private functions. Exported functions will not be renamed, and will
  # be defined normally, but calling them will require full qualification.

  @elixir_special_forms [
    :alias,
    :case,
    :cond,
    :for,
    :import,
    :quote,
    :receive,
    :require,
    :super,
    :try,
    :with
  ] |> Enum.into(MapSet.new)


  # These names are allowed as names of functions or variables, but clash with
  # auto-imported functions/macros from Kernel.
  # The converter will allow variables with these names, but will attempt to
  # rename private functions. Exported functions will not be renamed, and will
  # be defined normally, but calling them (and calling the Kernel functions of
  # the same name) will require full qualification.

  @elixir_auto_imports [
    # Kernel functions
    abs: 1,
    apply: 2,
    apply: 3,
    binary_part: 3,
    bit_size: 1,
    byte_size: 1,
    div: 2,
    elem: 2,
    exit: 1,
    function_exported?: 3,
    get_and_update_in: 3,
    get_in: 2,
    hd: 1,
    inspect: 2,
    is_atom: 1,
    is_binary: 1,
    is_bitstring: 1,
    is_boolean: 1,
    is_float: 1,
    is_function: 1,
    is_function: 2,
    is_integer: 1,
    is_list: 1,
    is_map: 1,
    is_number: 1,
    is_pid: 1,
    is_port: 1,
    is_reference: 1,
    is_tuple: 1,
    length: 1,
    macro_exported?: 3,
    make_ref: 0,
    map_size: 1,
    max: 2,
    min: 2,
    node: 0,
    node: 1,
    not: 1,
    put_elem: 3,
    put_in: 3,
    rem: 2,
    round: 1,
    self: 0,
    send: 2,
    spawn: 1,
    spawn: 3,
    spawn_link: 1,
    spawn_link: 3,
    spawn_monitor: 1,
    spawn_monitor: 3,
    struct: 2,
    struct!: 2,
    throw: 1,
    tl: 1,
    trunc: 1,
    tuple_size: 1,
    update_in: 3,

    # Kernel macros
    alias!: 1,
    and: 2,
    binding: 1,
    def: 2,
    defdelegate: 2,
    defexception: 1,
    defimpl: 3,
    defmacro: 2,
    defmacrop: 2,
    defmodule: 2,
    defoverridable: 1,
    defp: 2,
    defprotocol: 2,
    defstruct: 1,
    destructure: 2,
    get_and_update_in: 2,
    if: 2,
    in: 2,
    is_nil: 1,
    match?: 2,
    or: 2,
    put_in: 2,
    raise: 1,
    raise: 2,
    reraise: 2,
    reraise: 3,
    sigil_C: 2,
    sigil_R: 2,
    sigil_S: 2,
    sigil_W: 2,
    sigil_c: 2,
    sigil_r: 2,
    sigil_s: 2,
    sigil_w: 2,
    to_char_list: 1,
    to_string: 1,
    unless: 2,
    update_in: 2,
    use: 2,
    var!: 2,
  ] |> Enum.reduce(%{}, fn({k, v}, m) ->
    Map.update(m, k, [], fn list -> [v | list] end)
  end)


  # Attributes that have a semantic meaning to Erlang.

  @special_attribute_names [
    :callback,
    :else,
    :endif,
    :export,
    :export_type,
    :file,
    :ifdef,
    :ifndef,
    :include,
    :include_lib,
    :module,
    :opaque,
    :record,
    :spec,
    :type,
    :undef,
  ] |> Enum.into(MapSet.new)


  def elixir_reserved_words, do: @elixir_reserved_words

  def elixir_auto_imports, do: @elixir_auto_imports


  # Returns true if the given name is an attribute with a semantic meaning
  # to Erlang.

  def special_attr_name?(name), do:
    MapSet.member?(@special_attribute_names, name)


  # Returns true if the given name can be a function called by name using
  # normal qualified syntax. e.g. :foo, :def, and :nil are callable because you
  # can say Kernel.nil(). However, :"9foo" is not callable. If a function name
  # is not callable, you have to use Kernel.apply() to call it.

  def callable_function_name?(name), do:
    Regex.match?(~r/^[_a-z]\w*$/, Atom.to_string(name)) and
        not MapSet.member?(@elixir_uncallable_functions, name)


  # Returns true if the given name can be a function defined using "def"
  # syntax. If a function name is not deffable, you have to use a macro to
  # muck with the AST in order to define it.

  def deffable_function_name?(name), do:
    callable_function_name?(name) and not MapSet.member?(@elixir_reserved_words, name)


  # Returns true if the given function name can be called without module
  # qualification.

  def local_callable_function_name?(name), do:
    deffable_function_name?(name) and not MapSet.member?(@elixir_special_forms, name)


  # Returns {:ok, elixir_module, elixir_func} or :error depending on whether
  # the given Erlang BIF corresponds to an Elixir autoimport.

  def map_bif(name) do
    case Map.fetch(@bif_map, name) do
      {:ok, {mod, func}} -> {:ok, mod, func}
      {:ok, kernel_func} -> {:ok, Kernel, kernel_func}
      :error -> :error
    end
  end

end
