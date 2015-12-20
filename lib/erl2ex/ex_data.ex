
defmodule Erl2ex.ExAttr do

  defstruct name: nil,
            tracking_name: nil,
            arg: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExDirective do

  defstruct directive: nil,
            name: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExImport do

  defstruct module: nil,
            funcs: [],
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExMacro do

  defstruct signature: nil,
            tracking_name: nil,
            expr: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExFunc do

  defstruct name: nil,
            arity: nil,
            public: false,
            clauses: [],
            comments: []

end


defmodule Erl2ex.ExClause do

  defstruct signature: nil,
            exprs: [],
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExModule do

  defstruct name: nil,
            comments: [],
            forms: []

end
