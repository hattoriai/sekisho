defmodule Sekisho.Migrations.V1 do
  @moduledoc false
  # The grants (Sekisho.Grant) and the roles records define (Sekisho.Role).

  use PhoenixMountable.Migration, description: "Sekisho's grants"

  def up(ctx) do
    id = if ctx.install_options["primary_key"] == "binary_id", do: :uuid, else: :bigint

    create table(:sekisho_grants, prefix: ctx.prefix) do
      add :resource_type, :text, null: false
      add :resource_id, id, null: false
      add :actor_type, :text, null: false
      add :actor_id, id
      add :role, :text, null: false
      add :token_hash, :binary
      add :granted_by_id, id
      add :expires_at, :utc_datetime_usec

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    # One grant of a role to someone on a record; the records of a type an
    # actor holds roles on; a link by its token.
    create unique_index(
             :sekisho_grants,
             [:resource_type, :resource_id, :actor_type, :actor_id, :role],
             prefix: ctx.prefix
           )

    create index(:sekisho_grants, [:actor_type, :actor_id, :resource_type], prefix: ctx.prefix)

    # The roles a record defines for itself, by its name.
    create table(:sekisho_roles, prefix: ctx.prefix) do
      add :resource_type, :text, null: false
      add :resource_id, id, null: false
      add :name, :text, null: false
      add :permissions, {:array, :text}, null: false, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sekisho_roles, [:resource_type, :resource_id, :name], prefix: ctx.prefix)

    create unique_index(:sekisho_grants, [:token_hash],
             prefix: ctx.prefix,
             where: "token_hash IS NOT NULL"
           )
  end

  def down(ctx) do
    drop table(:sekisho_roles, prefix: ctx.prefix)
    drop table(:sekisho_grants, prefix: ctx.prefix)
  end
end
