defmodule Sekisho.SQL.Dialect.Postgres do
  @moduledoc "PostgreSQL: a grant made or made again in one statement."
  use Sekisho.SQL.Dialect

  @impl true
  defdelegate upsert_grant(repo, grant), to: Sekisho.SQL.Dialect.Standard, as: :on_conflict_upsert
end
