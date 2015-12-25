
defmodule Erl2ex.ExAttr do
  @moduledoc false

  defstruct name: nil,
            tracking_name: nil,
            register: false,
            arg: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExDirective do
  @moduledoc false

  defstruct directive: nil,
            name: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExImport do
  @moduledoc false

  defstruct module: nil,
            funcs: [],
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExMacro do
  @moduledoc false

  defstruct signature: nil,
            tracking_name: nil,
            expr: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExRecord do
  @moduledoc false

  defstruct tag: nil,
            macro: nil,
            fields: [],
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExType do
  @moduledoc false

  defstruct kind: nil,
            signature: nil,
            defn: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExCallback do
  @moduledoc false

  defstruct name: nil,
            specs: [],
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExHeader do
  @moduledoc false

  defstruct use_bitwise: false,
            records: [],
            record_info_available: false

end


defmodule Erl2ex.ExFunc do
  @moduledoc false

  defstruct name: nil,
            arity: nil,
            public: false,
            specs: [],
            clauses: [],
            comments: []

end


defmodule Erl2ex.ExClause do
  @moduledoc false

  defstruct signature: nil,
            exprs: [],
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExModule do
  @moduledoc false

  defstruct name: nil,
            comments: [],
            forms: []

end
