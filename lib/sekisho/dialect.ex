defmodule Sekisho.Dialect do
  @moduledoc """
  What Sekisho does differently on one SQL database: the only place it
  does.

  Everything else is plain Ecto that every SQL database runs (joins,
  `UNION`, `EXISTS`, a recursive `WITH` for nested records). Where a
  database has a faster way, or needs another column type, a dialect says
  so:

    * `c:upsert_grant/2`: a grant made, or made again (its expiry and who
      gave it updated). The default reads, then writes, in a transaction;
      PostgreSQL and SQLite do it in one statement.
    * `c:column/1`: the type of a column of Sekisho's tables, where the
      default does not fit.

  Sekisho picks the dialect from the repo's adapter: `Sekisho.Dialect.Postgres`,
  `Sekisho.Dialect.SQLite`, `Sekisho.Dialect.MySQL`, and
  `Sekisho.Dialect.Standard` for any other. For another database, write a
  module with `use Sekisho.Dialect`, override what differs, and name it
  for its adapter:

      config :sekisho, :dialects, %{Ecto.Adapters.Tds => MyApp.TdsDialect}

  It counts for the migrations too, so set it before you run them.
  """

  alias Sekisho.Grant

  @doc "Inserts the grant, or updates the one of the same record, grantee and role."
  @callback upsert_grant(repo :: module(), Grant.t()) ::
              {:ok, Grant.t()} | {:error, Ecto.Changeset.t()}

  @doc "The type and options of a column of Sekisho's tables (`:token_hash`)."
  @callback column(name :: atom()) :: {atom(), keyword()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Sekisho.Dialect

      @impl Sekisho.Dialect
      defdelegate upsert_grant(repo, grant), to: Sekisho.Dialect.Standard

      @impl Sekisho.Dialect
      defdelegate column(name), to: Sekisho.Dialect.Standard

      defoverridable upsert_grant: 2, column: 1
    end
  end

  @builtin %{
    Ecto.Adapters.Postgres => Sekisho.Dialect.Postgres,
    Ecto.Adapters.SQLite3 => Sekisho.Dialect.SQLite,
    Ecto.Adapters.MyXQL => Sekisho.Dialect.MySQL
  }

  @doc "The dialect of a repo: the app's for its adapter, else Sekisho's, else the standard one."
  def for_repo(repo) do
    adapter = repo.__adapter__()

    Map.get(Application.get_env(:sekisho, :dialects, %{}), adapter) ||
      Map.get(@builtin, adapter, Sekisho.Dialect.Standard)
  end
end

defmodule Sekisho.Dialect.Standard do
  @moduledoc """
  The dialect of any SQL database: what every other one starts from.
  """

  @behaviour Sekisho.Dialect

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

defmodule Sekisho.Dialect.Postgres do
  @moduledoc "PostgreSQL: a grant made or made again in one statement."
  use Sekisho.Dialect

  @impl true
  defdelegate upsert_grant(repo, grant), to: Sekisho.Dialect.Standard, as: :on_conflict_upsert
end

defmodule Sekisho.Dialect.SQLite do
  @moduledoc "SQLite: a grant made or made again in one statement."
  use Sekisho.Dialect

  @impl true
  defdelegate upsert_grant(repo, grant), to: Sekisho.Dialect.Standard, as: :on_conflict_upsert
end

defmodule Sekisho.Dialect.MySQL do
  @moduledoc "MySQL and MariaDB: an indexed binary column has a length (a varbinary)."
  use Sekisho.Dialect

  @impl true
  def column(:token_hash), do: {:varbinary, size: 32}
end
