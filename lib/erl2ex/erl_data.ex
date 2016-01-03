
defmodule Erl2ex.ErlComment do
  @moduledoc false

  defstruct comments: []

end


defmodule Erl2ex.ErlAttr do
  @moduledoc false

  defstruct line: nil,
            name: nil,
            arg: nil,
            comments: []

end


defmodule Erl2ex.ErlImport do
  @moduledoc false

  defstruct line: nil,
            module: nil,
            funcs: [],
            comments: []

end


defmodule Erl2ex.ErlDefine do
  @moduledoc false

  defstruct line: nil,
            name: nil,
            args: nil,
            stringifications: nil,
            replacement: nil,
            comments: []

end


defmodule Erl2ex.ErlDirective do
  @moduledoc false

  defstruct line: nil,
            directive: nil,
            name: nil,
            comments: []

end


defmodule Erl2ex.ErlRecord do
  @moduledoc false

  defstruct line: nil,
            name: nil,
            fields: [],
            comments: []

end


defmodule Erl2ex.ErlType do
  @moduledoc false

  defstruct line: nil,
            kind: nil,
            name: nil,
            params: [],
            defn: nil,
            comments: []

end


defmodule Erl2ex.ErlSpec do
  @moduledoc false

  defstruct line: nil,
            name: nil,
            clauses: [],
            comments: []

end


defmodule Erl2ex.ErlFunc do
  @moduledoc false

  defstruct name: nil,
            arity: nil,
            clauses: [],
            comments: []

end


defmodule Erl2ex.ErlModule do
  @moduledoc false

  defstruct name: nil,
            comments: [],
            exports: [],
            type_exports: [],
            imports: [],
            specs: [],
            forms: []

end
