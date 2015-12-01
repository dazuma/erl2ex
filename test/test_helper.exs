defmodule TestFixtures do

  def test1_erl_source() do
    """
    % This is a test module

    -module(test1).
    -export([one/1]).
    -vsn(123).

    % This is a one function
    % which calls eql.
    one(X) ->
      Y = X - 1,
      % inline comment
      eql(Y, 0).

    % A multi-clause function
    eql(X, X) when X >= 0 -> true;
    % the second clause
    eql(_, _) -> false.

    % after comment
    """
  end


  def test1_erl_module() do
    %Erl2ex.ErlModule{
      name: :test1,
      comments: [
        {:comment, 1, '% This is a test module'}
      ],
      exports: [one: 1],
      forms: [
        %Erl2ex.ErlAttr{line: 5, name: :vsn, arg: 123, comments: []},
        %Erl2ex.ErlFunc{
          name: :one,
          arity: 1,
          clauses: [
            %Erl2ex.ErlClause{
              line: 9,
              args: [{:var, 9, :X}],
              guards: [],
              exprs: [
                {:match, 10,
                  {:var, 10, :Y},
                  {:op, 10, :-, {:var, 10, :X}, {:integer, 10, 1}}
                },
                {:call, 12, {:atom, 12, :eql}, [
                  {:var, 12, :Y},
                  {:integer, 12, 0}
                ]}
              ]
            }
          ],
          comments: [
            {:comment, 7, '% This is a one function'},
            {:comment, 8, '% which calls eql.'},
            {:comment, 11, '% inline comment'}
          ]
        },
        %Erl2ex.ErlFunc{
          name: :eql,
          arity: 2,
          clauses: [
            %Erl2ex.ErlClause{
              line: 15,
              args: [{:var, 15, :X}, {:var, 15, :X}],
              guards: [[{:op, 15, :>=, {:var, 15, :X}, {:integer, 15, 0}}]],
              exprs: [
                {:atom, 15, :true}
              ]
            },
            %Erl2ex.ErlClause{
              line: 17,
              args: [{:var, 17, :_}, {:var, 17, :_}],
              guards: [],
              exprs: [
                {:atom, 17, :false}
              ]
            }
          ],
          comments: [
            {:comment, 14, '% A multi-clause function'},
            {:comment, 16, '% the second clause'}
          ]
        }
      ],
    }
  end


  def test1_ex_module do
    %Erl2ex.ExModule{
      name: :test1,
      comments: ["# This is a test module"],
      forms: [
        %Erl2ex.ExAttr{arg: 123, comments: [], inline_comments: [], name: :vsn},
        %Erl2ex.ExFunc{
          name: :one,
          arity: 1,
          public: true,
          clauses: [
            %Erl2ex.ExClause{
              args: [{:x, [], Elixir}],
              guard: nil,
              exprs: [
                {:=, [], [{:y, [], Elixir}, {:-, [context: Elixir, import: Kernel], [{:x, [], Elixir}, 1]}]},
                {:eql, [], [{:y, [], Elixir}, 0]}
              ],
              comments: [],
              inline_comments: ["# inline comment"]
            }
          ],
          comments: [
            "# This is a one function",
            "# which calls eql."
          ]
        },
        %Erl2ex.ExFunc{
          name: :eql,
          arity: 2,
          public: false,
          clauses: [
            %Erl2ex.ExClause{
              args: [
                {:x, [], Elixir},
                {:x, [], Elixir}
              ],
              guard: {:>=, [context: Elixir, import: Kernel], [{:x, [], Elixir}, 0]},
              exprs: [true],
              comments: [],
              inline_comments: []
            },
            %Erl2ex.ExClause{
              args: [
                {:_, [], Elixir},
                {:_, [], Elixir}
              ],
              guard: nil,
              exprs: [false],
              comments: ["# the second clause"],
              inline_comments: []
            }
          ],
          comments: ["# A multi-clause function"]
        }
      ]
    }
  end


  def test1_ex_source do
    """
    # This is a test module
    defmodule :test1 do
      @vsn 123


      # This is a one function
      # which calls eql.
      def one(x) do
        y = x - 1
        eql(y, 0)
      end


      # A multi-clause function
      defp eql(x, x) when x >= 0 do
        true
      end

      # the second clause
      defp eql(_, _) do
        false
      end

    end
    """
  end

end


ExUnit.start()
