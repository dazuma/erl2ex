defmodule Erl2ex.Mixfile do
  use Mix.Project

  def project do
    [
      app: :erl2ex,
      version: "0.0.1",
      elixir: "~> 1.1",
      name: "Erl2ex",
      source_url: "https://github.com/dazuma/erl2ex",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      escript: [main_module: Erl2ex.Cli],
      deps: deps,
      docs: docs,
      description: description,
      package: package
    ]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [
      {:earmark, "~> 0.1", only: :dev},
      {:ex_doc, "~> 0.11", only: :dev}
    ]
  end

  defp docs do
    [
      extras: ["README.md", "LICENSE.md", "TODO.md"]
    ]
  end

  defp description do
    """
    Erl2ex is an Erlang to Elixir transpiler, converting well-formed Erlang
    source to Elixir source with equivalent functionality.
    The goal is to produce correct, functioning Elixir code, but not necessarily
    perfectly idiomatic. This tool may be used as a starting point when porting
    code from Erlang to Elixir, but manual cleanup will likely be desired.
    """
  end

  defp package do
    [
      maintainers: ["Daniel Azuma"],
      licenses: ["BSD"],
      links: %{"GitHub" => "https://github.com/dazuma/erl2ex"}
    ]
  end

end
