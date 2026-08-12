defmodule ExParamsSchema.MixProject do
  use Mix.Project

  @source_url "https://github.com/nasshu2916/ex_params_schema"

  def project do
    [
      app: :ex_params_schema,
      version: "0.1.1",
      description: "Converts and validates string-oriented params into typed Elixir values",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      dialyzer: [plt_add_apps: [:mix]],
      test_coverage: [summary: [threshold: 90]],
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_json_schema, "~> 0.11.4"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end

  defp package do
    [
      name: "ex_params_schema",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ["lib", "mix.exs", "README.md", "README_ja.md", "CHANGELOG.md", "LICENSE", "docs"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        {"README.md", title: "ExParamsSchema", filename: "readme"},
        "CHANGELOG.md",
        "docs/development.md",
        "docs/dsl.md",
        "docs/json-schema-usage.md",
        "docs/parsing-semantics.md",
        {"README_ja.md", title: "ExParamsSchema (日本語)", filename: "readme_ja"},
        {"docs/development_ja.md", title: "開発ガイド", filename: "development_ja"},
        {"docs/dsl_ja.md", title: "DSL リファレンス", filename: "dsl_ja"},
        {"docs/json-schema-usage_ja.md", title: "`json_schema:` の使い方", filename: "json-schema-usage_ja"},
        {"docs/parsing-semantics_ja.md", title: "パースの仕様", filename: "parsing-semantics_ja"}
      ]
    ]
  end
end
