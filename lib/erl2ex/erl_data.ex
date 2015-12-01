
defmodule Erl2ex.ErlAttr do

  defstruct line: nil,
            name: nil,
            arg: nil,
            comments: []

end


defmodule Erl2ex.ErlFunc do

  defstruct name: nil,
            arity: nil,
            clauses: [],
            comments: []

end


defmodule Erl2ex.ErlClause do

  defstruct line: nil,
            args: [],
            guards: [],
            exprs: []

end


defmodule Erl2ex.ErlModule do

  defstruct name: nil,
            comments: [],
            exports: [],
            forms: []

end
