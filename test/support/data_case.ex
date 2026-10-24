defmodule SekishoTest.DataCase do
  @moduledoc "Tests with the database (Ecto's sandbox) and the fixtures."
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import SekishoTest.DataCase

      alias SekishoTest.{
        Document,
        Folder,
        Org,
        Permissions,
        Post,
        Project,
        Repo,
        Scope,
        Team,
        User
      }
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(SekishoTest.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  def insert!(struct), do: SekishoTest.Repo.insert!(struct)

  def user!(attrs \\ []),
    do: insert!(struct!(SekishoTest.User, Keyword.put_new(attrs, :name, "someone")))

  def scope(nil), do: %SekishoTest.Scope{}
  def scope(user, links \\ []), do: %SekishoTest.Scope{user: user, links: links}
end
