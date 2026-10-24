defmodule Sekisho.Migrations.V1 do
  @moduledoc false
  # The grants (Sekisho.Grant), the roles records define (Sekisho.Role) and
  # their permissions (Sekisho.RolePermission).
  #
  # The same tables on every SQL database: a role's permissions are rows,
  # not an array; the columns in an index have a length; the links' unique
  # index is a plain one (SQL lets several NULLs through it). A column a
  # database types its own way comes from its dialect (Sekisho.Dialect).

  use PhoenixMountable.Migration, description: "Sekisho's grants"

  def up(ctx) do
    id = if ctx.install_options["primary_key"] == "binary_id", do: :uuid, else: :bigint
    {hash_type, hash_opts} = Sekisho.Dialect.for_repo(ctx.repo).column(:token_hash)

    create table(:sekisho_grants, prefix: ctx.prefix) do
      add :resource_type, :string, size: 64, null: false
      add :resource_id, id, null: false
      add :actor_type, :string, size: 64, null: false
      add :actor_id, id
      add :role, :string, size: 100, null: false
      add :token_hash, hash_type, hash_opts
      add :granted_by_id, id
      add :expires_at, :utc_datetime_usec

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    # One grant of a role to someone on a record; the records of a type an
    # actor holds roles on; a link by its token.
    # Named: the name Ecto makes is longer than MySQL takes (64).
    create unique_index(
             :sekisho_grants,
             [:resource_type, :resource_id, :actor_type, :actor_id, :role],
             name: :sekisho_grants_unique_index,
             prefix: ctx.prefix
           )

    create index(:sekisho_grants, [:actor_type, :actor_id, :resource_type], prefix: ctx.prefix)
    create unique_index(:sekisho_grants, [:token_hash], prefix: ctx.prefix)

    # The roles a record defines for itself, by its name.
    create table(:sekisho_roles, primary_key: false, prefix: ctx.prefix) do
      add :id, :bigserial, primary_key: true
      add :resource_type, :string, size: 64, null: false
      add :resource_id, id, null: false
      add :name, :string, size: 100, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sekisho_roles, [:resource_type, :resource_id, :name], prefix: ctx.prefix)

    # What each of those roles gives, a permission a row.
    create table(:sekisho_role_permissions, prefix: ctx.prefix) do
      add :role_id,
          references(:sekisho_roles,
            type: :bigserial,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false

      add :permission, :string, size: 100, null: false
    end

    create unique_index(:sekisho_role_permissions, [:role_id, :permission], prefix: ctx.prefix)
  end

  def down(ctx) do
    drop table(:sekisho_role_permissions, prefix: ctx.prefix)
    drop table(:sekisho_roles, prefix: ctx.prefix)
    drop table(:sekisho_grants, prefix: ctx.prefix)
  end
end
