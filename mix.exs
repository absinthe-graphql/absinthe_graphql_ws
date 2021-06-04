defmodule AbsintheGraphqlWS.MixProject do
  use Mix.Project

  @version "0.1.0"
  def project do
    [
      app: :absinthe_graphql_ws,
      deps: deps(),
      description: "Add graphql-ws websocket transport for Absinthe",
      dialyzer: dialyzer(),
      docs: docs(),
      elixir: "~> 1.12",
      homepage_url: "https://github.com/geometerio/absinthe_graphql_ws",
      name: "AbsintehGrahqlWS",
      package: package(),
      preferred_cli_env: [credo: :test],
      source_url: "https://github.com/geometerio/absinthe_graphql_ws",
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix],
      plt_add_deps: :app_tree,
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end


  defp docs do
    [
      extras: [
        "guides/overview.md",
        "README.md"
      ],
      main: "overview",
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Geometer"],
      links: %{"GitHub" => "https://github.com/geometerio/absinthe_graphql_ws"}
    ]
  end
end
