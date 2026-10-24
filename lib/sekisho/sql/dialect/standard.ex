defmodule Sekisho.SQL.Dialect.Standard do
  @moduledoc """
  The dialect of any SQL database: what every other one starts from.
  """

  @behaviour Sekisho.SQL.Dialect

  import Ecto.Query

  alias Sekisho.Grant

  @impl true
  def upsert_grant(repo, %Grant{} = grant) do
    repo.transaction(fn ->
      existing =
        repo.one(
          from g in Grant,
            where:
              g.resource_type == ^grant.resource_type and g.resource_id == ^grant.resource_id,
            where: g.actor_type == ^grant.actor_type and g.actor_id == ^grant.actor_id,
            where: g.role == ^grant.role
        )

      result =
        case existing do
          nil ->
            repo.insert(grant)

          existing ->
            existing
            |> Ecto.Changeset.change(
              expires_at: grant.expires_at,
              granted_by_id: grant.granted_by_id
            )
            |> repo.update()
        end

      case result do
        {:ok, grant} -> grant
        {:error, changeset} -> repo.rollback(changeset)
      end
    end)
  end

  @impl true
  def column(:token_hash), do: {:binary, []}

  @doc false
  # One statement: INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING.
  def on_conflict_upsert(repo, %Grant{} = grant) do
    repo.insert(grant,
      on_conflict: {:replace, [:expires_at, :granted_by_id]},
      conflict_target: [:resource_type, :resource_id, :actor_type, :actor_id, :role],
      returning: true
    )
  end
end
