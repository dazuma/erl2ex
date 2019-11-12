# These internal data structures are the output of Pipeline.Convert, and
# represent Elixir source trees for codegen.

# A toplevel comment.

defmodule Erl2ex.Pipeline.ExComment do
  @moduledoc false

  defstruct(
    # List of comments, one per line. Each comment must begin with a hash "#".
    comments: []
  )
end

# A module attribute.

defmodule Erl2ex.Pipeline.ExAttr do
  @moduledoc false

  defstruct(
    # Name of the attribute as an atom.
    name: nil,
    # Whether to register the attribute.
    register: false,
    # List of arguments. Most attributes have a single argument (the value).
    arg: nil,
    # List of pre-form comments, one per line. Each must begin with a hash "#".
    comments: []
  )
end

# The Elixir form of an Erlang compiler directive (such as ifdef).
# This is represented as an abstract directive here, and codegen takes care
# of generating Elixir compile-time code.

defmodule Erl2ex.Pipeline.ExDirective do
  @moduledoc false

  defstruct(
    # The directive as an atom.
    directive: nil,
    # The name of the referenced name (e.g. the macro name for ifdef) as an atom.
    name: nil,
    # List of pre-form comments, one per line. Each must begin with a hash "#".
    comments: []
  )
end

# A directive to import a module.

defmodule Erl2ex.Pipeline.ExImport do
  @moduledoc false

  defstruct(
    # The name of the module, as an atom.
    module: nil,
    # List of functions to import, each as {name_as_atom, arity_as_integer}.
    funcs: [],
    # List of pre-form comments, one per line. Each must begin with a hash "#".
    comments: []
  )
end

# An Elixir macro

defmodule Erl2ex.Pipeline.ExMacro do
  @moduledoc false

  defstruct(
    # Elixir AST for the signature of the macro
    signature: nil,
    # The macro name as an atom.
    macro_name: nil,
    # The name of an attribute that tracks whether the macro is defined, as an atom.
    tracking_name: nil,
    # The name of an attribute that tracks the current macro name, as an atom.
    # Used when a macro is redefined in a module, which Elixir doesn't allow. So we
    # define macros with different names, and use this attribute to specify which name
    # we are using.
    dispatch_name: nil,
    # A map from argument name (as atom) to a variable name used for the stringified
    # form of the argument (i.e. the Erlang "??" preprocessor operator).
    stringifications: nil,
    # Elixir AST for the macro replacement when expanded in normal context.
    expr: nil,
    # Elixir AST for the macro replacement when expanded in a guard context, or
    # nil if the expansion should not be different from normal context.
    guard_expr: nil,
    # List of pre-form comments, one per line. Each must begin with a hash "#".
    comments: []
  )
end

# An Elixir record.

defmodule Erl2ex.Pipeline.ExRecord do
  @moduledoc false

  defstruct(
    # The tag atom used in the record
    tag: nil,
    # The name of the record macro, as an atom.
    macro: nil,
    # The name of an attribute that stores the record definition.
    data_attr: nil,
    # The record fields, as Elixir AST.
    fields: [],
    # List of pre-form comments, one per line. Each must begin with a hash "#".
    comments: []
  )
end

# An Elixir type definition.

defmodule Erl2ex.Pipeline.ExType do
  @moduledoc false

  defstruct(
    # One of the following: :opaque, :type, :typep
    kind: nil,
    # An Elixir AST describing the type and its parameters (which may be empty).
    signature: nil,
    # Elixir AST describing the type's definition
    defn: nil,
    # List of pre-form comments, one per line. Each must begin with a hash "#".
    comments: []
  )
end

# An Elixir function spec.

defmodule Erl2ex.Pipeline.ExSpec do
  @moduledoc false

  defstruct(
    # Either :spec or :callback.
    kind: nil,
    # Name of the function specified.
    name: nil,
    # List of Elixir ASTs describing the specs.
    specs: [],
    # List of pre-form comments, one per line. Each must begin with a hash "#".
    comments: []
  )
end

# The header for an Elixir module. Includes auto-generated pieces such as
# require statements for Bitwise and Record, if needed, as well as various
# macros, attributes, etc. needed to implement Erlang semantics.

defmodule Erl2ex.Pipeline.ExHeader do
  @moduledoc false

  defstruct(
    # True if Bitwise operators are used in this module.
    use_bitwise: false,
    # True if the Erlang is_record BIF is used (so Elixir needs to require Record)
    has_is_record: false,
    # List of {record_name, [record_fields]} so codegen can define the records.
    records: [],
    # List of macro names that are not initialized explicitly and probably should be
    # initialized from environment variables.
    init_macros: [],
    # The name of the macro dispatcher macro (if needed) as an atom, or nil if the
    # dispatcher is not needed.
    macro_dispatcher: nil,
    # The name of the macro that returns record size, or nil if not needed.
    record_size_macro: nil,
    # The name of the macro that computes record index, or nil if not needed.
    record_index_macro: nil
  )
end

# An Elixir function.

defmodule Erl2ex.Pipeline.ExFunc do
  @moduledoc false

  defstruct(
    # The name of the function.
    name: nil,
    # Arity of the function, as an integer
    arity: nil,
    # Whether the function should be public.
    public: false,
    # Not currently used. Later we expect we'll consolidate specs for the function
    # here instead of emitting them separately.
    specs: [],
    # List of ExClause structures.
    clauses: [],
    # List of pre-form comments, one per line. Each must begin with a hash "#".
    comments: []
  )
end

# A single clause of an Elixir function.

defmodule Erl2ex.Pipeline.ExClause do
  @moduledoc false

  defstruct(
    # Elixir AST of the function signature.
    signature: nil,
    # List of Elixir ASTs representing the list of expressions in the function.
    exprs: [],
    # List of pre-form comments, one per line. Each must begin with a hash "#".
    comments: []
  )
end

# The full Elixir module representation.

defmodule Erl2ex.Pipeline.ExModule do
  @moduledoc false

  defstruct(
    # Name of the module, as an atom.
    name: nil,
    # List of top-of-file comments, one per line. Each must begin with a hash "#".
    file_comments: [],
    # List of top-of-module comments, one per line. These are indented within the
    # module definition. Each must begin with a hash "#".
    comments: [],
    # List of forms (other structures from this file).
    forms: []
  )
end
