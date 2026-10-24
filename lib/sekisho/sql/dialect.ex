defmodule Sekisho.SQL.Dialect do
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

  Sekisho picks the dialect from the repo's adapter: `Sekisho.SQL.Dialect.Postgres`,
  `Sekisho.SQL.Dialect.SQLite`, `Sekisho.SQL.Dialect.MySQL`, and
  `Sekisho.SQL.Dialect.Standard` for any other. For another database, write a
  module with `use Sekisho.SQL.Dialect`, override what differs, and name it
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
      @behaviour Sekisho.SQL.Dialect

      @impl Sekisho.SQL.Dialect
      defdelegate upsert_grant(repo, grant), to: Sekisho.SQL.Dialect.Standard

      @impl Sekisho.SQL.Dialect
      defdelegate column(name), to: Sekisho.SQL.Dialect.Standard

      defoverridable upsert_grant: 2, column: 1
    end
  end

  @builtin %{
    Ecto.Adapters.Postgres => Sekisho.SQL.Dialect.Postgres,
    Ecto.Adapters.SQLite3 => Sekisho.SQL.Dialect.SQLite,
    Ecto.Adapters.MyXQL => Sekisho.SQL.Dialect.MySQL
  }

  @doc "The dialect of a repo: the app's for its adapter, else Sekisho's, else the standard one."
  def for_repo(repo) do
    adapter = repo.__adapter__()

    Map.get(Application.get_env(:sekisho, :dialects, %{}), adapter) ||
      Map.get(@builtin, adapter, Sekisho.SQL.Dialect.Standard)
  end
end
