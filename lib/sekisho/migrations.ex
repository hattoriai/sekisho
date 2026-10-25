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

  Version 1 makes `sekisho_grants` (`Sekisho.Grant`), `sekisho_roles`
  (`Sekisho.Role`) and `sekisho_role_permissions`
  (`Sekisho.RolePermission`), the same on every SQL database; a column a
  database types its own way comes from its dialect (`Sekisho.SQL.Dialect`).

  ## The type of the ids

  The ids of the grants are of the type of your app's records: `:id`
  (bigint) or `:binary_id` (uuid), from your repo's `:migration_primary_key`,
  or `up(version: 1, primary_key: :binary_id)`. When the records granted on
  and the users and groups granted to have ids of different types, give
  each:

    * `:resource_key`: the ids of the records granted on (and of those that
      define roles), `:id` or `:binary_id`.
    * `:actor_key`: the ids of the users and groups granted to, and of who
      gave each grant, `:id` or `:binary_id`.

  Each defaults to `:primary_key`. They are kept with the version, so later
  versions use them too.

  ## Tables of their own

  A library that keeps permissions of its own in its host's database (its
  reports, granted to the host's users) keeps them in tables of its own, so
  its grants, its versions and its rollbacks never touch the host's Sekisho.
  It names them in its permissions module (`use Sekisho, tables: "my_lib"`),
  and migrates them with a module of its own:

      defmodule MyLib.Migrations.Permissions do
        use Sekisho.Migrations, tables: "my_lib"
      end

      MyLib.Migrations.Permissions.up(version: 1, resource_key: :id)

  That makes `my_lib_grants`, `my_lib_roles` and `my_lib_role_permissions`,
  tracked apart from Sekisho's own (as `"sekisho:my_lib"`), with the same
  versions.
  """

  @install_options [
    primary_key: [type: {:in, [:id, :binary_id]}],
    resource_key: [type: {:in, [:id, :binary_id]}],
    actor_key: [type: {:in, [:id, :binary_id]}]
  ]

  use PhoenixMountable.Migrations,
    otp_app: :sekisho,
    versions: [Sekisho.Migrations.V1],
    install_options: @install_options,
    gen_task: "sekisho.gen.migration"

  @doc false
  def __sekisho_tables__, do: "sekisho"

  @doc false
  defmacro __using__(opts) do
    tables = opts |> Keyword.fetch!(:tables) |> Sekisho.Tables.check!()

    if tables == "sekisho" do
      raise ArgumentError,
            "tables: \"sekisho\" are Sekisho.Migrations' own: name tables of your own"
    end

    quote do
      use PhoenixMountable.Migrations,
        otp_app: :sekisho,
        library: unquote("sekisho:" <> tables),
        versions: [Sekisho.Migrations.V1],
        install_options: unquote(Macro.escape(@install_options))

      @doc false
      def __sekisho_tables__, do: unquote(tables)
    end
  end
end
