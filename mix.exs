defmodule Sekisho.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/hattoriai/sekisho"

  def project do
    [
      app: :sekisho,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/project.plt"}
      ],
      package: package(),
      docs: docs(),
      description: description(),
      name: "Sekisho",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      # The conditions, the lists and the grants: Ecto queries in the app's
      # database, whichever SQL database it is. The tests run on PostgreSQL.
      {:ecto, "~> 3.13"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.19", only: :test},
      # The tables' versions (Sekisho.Migrations), the installer, and the
      # optional screens.
      {:phoenix_mountable, "~> 0.2.5"},
      # Sekisho.LiveView: events checked, and pages that lose their access.
      {:phoenix_live_view, "~> 1.1", optional: true},
      {:lazy_html, "~> 0.1", only: :test},
      # mix sekisho.install. Without it, the task says what to do by hand.
      {:igniter, "~> 0.6", optional: true},
      # Grants given and revoked, broadcast to the app's processes.
      {:phoenix_pubsub, "~> 2.1", optional: true},
      {:telemetry, "~> 1.0"}
    ]
  end

  defp description do
    "Permissions for Phoenix: from a simple check to roles, sharing and inherited access, in your own database."
  end

  defp package do
    [
      name: "sekisho",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib guides mix.exs .formatter.exs README.md CHANGELOG.md LICENSE NOTICE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      assets: %{"media" => "media"},
      extras: [
        "README.md",
        "guides/quickstart.md",
        "guides/rules.md",
        "guides/rbac.md",
        "guides/rebac.md",
        "guides/abac.md",
        "guides/hybrid.md",
        "guides/sources.md",
        "guides/phoenix.md",
        "guides/testing.md",
        "guides/queries.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/(quickstart|rules|rbac|rebac|abac|hybrid)/,
        "In your app": ~r/guides\/(sources|phoenix|testing|queries)/
      ],
      groups_for_modules: [
        "Your modules": [Sekisho, Sekisho.Policy, Sekisho.Sources],
        Phoenix: [Sekisho.LiveView],
        Results: [
          Sekisho.Denied,
          Sekisho.Explanation,
          Sekisho.Grant,
          Sekisho.Role,
          Sekisho.RolePermission
        ],
        Tables: [Sekisho.Migrations],
        Databases: [
          Sekisho.SQL.Dialect,
          Sekisho.SQL.Dialect.Standard,
          Sekisho.SQL.Dialect.Postgres,
          Sekisho.SQL.Dialect.SQLite,
          Sekisho.SQL.Dialect.MySQL
        ],
        Tests: [Sekisho.Test]
      ]
    ]
  end
end
