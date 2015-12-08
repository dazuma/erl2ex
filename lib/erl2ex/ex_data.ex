
defmodule Erl2ex.ExAttr do

  defstruct name: nil,
            arg: nil,
            comments: [],
            inline_comments: []

end


defmodule Erl2ex.ExMacro do

  defstruct signature: nil,
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
