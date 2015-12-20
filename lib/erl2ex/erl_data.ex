
defmodule Erl2ex.ErlAttr do

  defstruct line: nil,
            name: nil,
            arg: nil,
            comments: []

end


defmodule Erl2ex.ErlImport do

  defstruct line: nil,
            module: nil,
            funcs: [],
            comments: []

end


defmodule Erl2ex.ErlDefine do

  defstruct line: nil,
            name: nil,
            args: nil,
            replacement: nil,
            comments: []

end


defmodule Erl2ex.ErlDirective do

  defstruct line: nil,
            directive: nil,
            name: nil,
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
            imports: [],
            forms: []

end
