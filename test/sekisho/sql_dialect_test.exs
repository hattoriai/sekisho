defmodule Sekisho.SQL.DialectTest do
  # Which dialect a repo gets, and the standard one's grant, run here on
  # PostgreSQL: the code every other database runs.
  use SekishoTest.DataCase, async: false

  alias Sekisho.Grant
  alias Sekisho.SQL.Dialect

  defmodule OtherRepo do
    def __adapter__, do: Ecto.Adapters.Tds
  end

  defmodule TdsDialect do
    use Sekisho.SQL.Dialect
  end

  test "a repo gets its adapter's dialect, an unknown one the standard dialect" do
    assert Dialect.for_repo(Repo) == Dialect.Postgres
    assert Dialect.for_repo(OtherRepo) == Dialect.Standard
  end

  test "an app names the dialect of another adapter" do
    Application.put_env(:sekisho, :dialects, %{Ecto.Adapters.Tds => TdsDialect})
    on_exit(fn -> Application.delete_env(:sekisho, :dialects) end)

    assert Dialect.for_repo(OtherRepo) == TdsDialect
    assert TdsDialect.column(:token_hash) == {:binary, []}
  end

  test "the standard grant: made, then made again updates its expiry and who gave it" do
    doc = insert!(%Document{title: "nda"})
    ana = user!()
    owner = user!(name: "owner")
    later = DateTime.add(DateTime.utc_now(), 3600, :second)

    grant = %Grant{
      resource_type: "documents",
      resource_id: doc.id,
      actor_type: "users",
      actor_id: ana.id,
      role: "viewer"
    }

    assert {:ok, first} = Dialect.Standard.upsert_grant(Repo, grant)

    assert {:ok, again} =
             Dialect.Standard.upsert_grant(Repo, %{
               grant
               | expires_at: later,
                 granted_by_id: owner.id
             })

    assert again.id == first.id
    assert again.expires_at == later
    assert again.granted_by_id == owner.id
    assert Repo.aggregate(Grant, :count) == 1
  end
end
