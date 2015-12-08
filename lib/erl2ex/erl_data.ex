
defmodule Erl2ex.ErlAttr do

  defstruct line: nil,
            name: nil,
            arg: nil,
            comments: []

end


defmodule Erl2ex.ErlDefine do

  defstruct line: nil,
            macro: nil,
            replacement: nil,
            comments: []

end


defmodule Erl2ex.ErlFunc do

  defstruct name: nil,
            arity: nil,
            clauses: [],
            comments: []

end


defmodule Erl2ex.ErlModule do

  defstruct name: nil,
            comments: [],
            exports: [],
            forms: []

end
