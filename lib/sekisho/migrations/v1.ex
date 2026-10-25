defmodule Sekisho.Migrations.V1 do
  @moduledoc false
  # The grants (Sekisho.Grant), the roles records define (Sekisho.Role) and
  # their permissions (Sekisho.RolePermission).
  #
  # The same tables on every SQL database: a role's permissions are rows,
  # not an array; the columns in an index have a length; the links' unique
  # index is a plain one (SQL lets several NULLs through it). A column a
  # database types its own way comes from its dialect (Sekisho.SQL.Dialect).
  #
  # The tables are named from the migrations module (`tables:`), and the ids
  # typed from the install options: those of the records granted on, and
  # those of the users and groups granted to.

  use PhoenixMountable.Migration, description: "Sekisho's grants"

  alias Sekisho.SQL.Dialect
  alias Sekisho.Tables

  def up(ctx) do
    resource_id = id(ctx, "resource_key")
    actor_id = id(ctx, "actor_key")
    {hash_type, hash_opts} = Dialect.for_repo(ctx.repo).column(:token_hash)
    tables = ctx.migrations.__sekisho_tables__()
    grants = Tables.name(tables, :grants)
    roles = Tables.name(tables, :roles)
    role_permissions = Tables.name(tables, :role_permissions)

    create table(grants, prefix: ctx.prefix) do
      add :resource_type, :string, size: 64, null: false
      add :resource_id, resource_id, null: false
      add :actor_type, :string, size: 64, null: false
      add :actor_id, actor_id
      add :role, :string, size: 100, null: false
      add :token_hash, hash_type, hash_opts
      add :granted_by_id, actor_id
      add :expires_at, :utc_datetime_usec

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    # One grant of a role to someone on a record; the records of a type an
    # actor holds roles on; a link by its token.
    # Named: the name Ecto makes is longer than MySQL takes (64).
    create unique_index(
             grants,
             [:resource_type, :resource_id, :actor_type, :actor_id, :role],
             name: "#{grants}_unique_index",
             prefix: ctx.prefix
           )

    create index(grants, [:actor_type, :actor_id, :resource_type], prefix: ctx.prefix)
    create unique_index(grants, [:token_hash], prefix: ctx.prefix)

    # The roles a record defines for itself, by its name.
    create table(roles, primary_key: false, prefix: ctx.prefix) do
      add :id, :bigserial, primary_key: true
      add :resource_type, :string, size: 64, null: false
      add :resource_id, resource_id, null: false
      add :name, :string, size: 100, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(roles, [:resource_type, :resource_id, :name], prefix: ctx.prefix)

    # What each of those roles gives, a permission a row.
    create table(role_permissions, prefix: ctx.prefix) do
      add :role_id,
          references(roles,
            type: :bigserial,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false

      add :permission, :string, size: 100, null: false
    end

    create unique_index(role_permissions, [:role_id, :permission], prefix: ctx.prefix)
  end

  def down(ctx) do
    tables = ctx.migrations.__sekisho_tables__()

    for table <- [:role_permissions, :roles, :grants] do
      drop table(Tables.name(tables, table), prefix: ctx.prefix)
    end
  end

  # The column type of the ids of a kind, from its own option or from
  # :primary_key.
  defp id(ctx, option) do
    options = ctx.install_options
    key = options[option] || options["primary_key"]
    if key == "binary_id", do: :uuid, else: :bigint
  end
end
