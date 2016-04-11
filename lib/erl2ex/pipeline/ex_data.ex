
defmodule Erl2ex.Pipeline.ExComment do
  @moduledoc false

  defstruct comments: []

end


defmodule Erl2ex.Pipeline.ExAttr do
  @moduledoc false

  defstruct name: nil,
            register: false,
            arg: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.Pipeline.ExDirective do
  @moduledoc false

  defstruct directive: nil,
            name: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.Pipeline.ExImport do
  @moduledoc false

  defstruct module: nil,
            funcs: [],
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.Pipeline.ExMacro do
  @moduledoc false

  defstruct signature: nil,
            macro_name: nil,
            tracking_name: nil,
            dispatch_name: nil,
            stringifications: nil,
            expr: nil,
            guard_expr: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.Pipeline.ExRecord do
  @moduledoc false

  defstruct tag: nil,
            macro: nil,
            data_attr: nil,
            fields: [],
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.Pipeline.ExType do
  @moduledoc false

  defstruct kind: nil,
            signature: nil,
            defn: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.Pipeline.ExSpec do
  @moduledoc false

  defstruct kind: nil,
            name: nil,
            specs: [],
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.Pipeline.ExHeader do
  @moduledoc false

  defstruct use_bitwise: false,
            has_is_record: false,
            records: [],
            init_macros: [],
            macro_dispatcher: nil,
            record_size_macro: nil,
            record_index_macro: nil

end


defmodule Erl2ex.Pipeline.ExFunc do
  @moduledoc false

  defstruct name: nil,
            name_var: nil,
            arity: nil,
            public: false,
            specs: [],
            clauses: [],
            comments: []

end


defmodule Erl2ex.Pipeline.ExClause do
  @moduledoc false

  defstruct signature: nil,
            exprs: [],
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.Pipeline.ExModule do
  @moduledoc false

  defstruct name: nil,
            file_comments: [],
            comments: [],
            forms: []

end
