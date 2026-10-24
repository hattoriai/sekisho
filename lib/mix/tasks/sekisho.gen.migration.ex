defmodule Mix.Tasks.Sekisho.Gen.Migration do
  @shortdoc "Generates the migration that installs or upgrades Sekisho's tables"

  @moduledoc """
  Generates the migration of Sekisho's tables in your repo: the one that
  installs them, or, after an upgrade of Sekisho, the one that brings them
  to their latest version.

      $ mix sekisho.gen.migration
      $ mix sekisho.gen.migration --repo MyApp.Repo

  It is `mix phoenix_mountable.gen.migration Sekisho.Migrations` (see
  `Sekisho.Migrations`). Run it with `mix ecto.migrate`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args),
    do: Mix.Task.run("phoenix_mountable.gen.migration", ["Sekisho.Migrations" | args])
end
