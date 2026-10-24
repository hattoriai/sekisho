defmodule Sekisho.Grant do
  @moduledoc """
  A role given to someone on a record: a row of `sekisho_grants`.

  `actor_type` is the grantee's table (`"users"`, `"teams"`), or `"link"`
  for anyone with the link, whose `token` is set only in what `grant/4`
  returns: the table keeps its hash.

  The ids are of the type of your app's records (bigint or uuid, see
  `Sekisho.Migrations`), so the grants join your tables on their indexes.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sekisho_grants" do
    field :resource_type, :string
    field :resource_id, Sekisho.Id
    field :actor_type, :string
    field :actor_id, Sekisho.Id
    field :role, :string
    field :token_hash, :binary, redact: true
    field :token, :string, virtual: true, redact: true
    field :granted_by_id, Sekisho.Id
    field :expires_at, :utc_datetime_usec

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end
end
