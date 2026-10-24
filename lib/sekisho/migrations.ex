defmodule Sekisho.Migrations do
  @moduledoc """
  Sekisho's tables, in a migration of your app.

      $ mix sekisho.gen.migration

  writes a migration that pins the latest version:

      defmodule MyApp.Repo.Migrations.AddSekisho do
        use Ecto.Migration

        def up, do: Sekisho.Migrations.up(version: 1)
        def down, do: Sekisho.Migrations.down(to: 0)
      end

  The versions are `PhoenixMountable.Migrations`, tracked in your database.
  A later version of Sekisho that changes its tables has a new version, and
  `mix sekisho.gen.migration` writes the migration that upgrades.

  The ids of the grants are of the type of your app's records: `:id`
  (bigint) or `:binary_id` (uuid), from your repo's `:migration_primary_key`,
  or `up(version: 1, primary_key: :binary_id)`. It is kept with the version,
  so later versions use it too.

  Version 1 makes `sekisho_grants` (`Sekisho.Grant`) and `sekisho_roles`
  (`Sekisho.Role`).
  """

  use PhoenixMountable.Migrations,
    otp_app: :sekisho,
    versions: [Sekisho.Migrations.V1],
    install_options: [primary_key: [type: {:in, [:id, :binary_id]}]],
    gen_task: "sekisho.gen.migration"
end
