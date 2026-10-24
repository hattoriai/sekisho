defmodule Sekisho.EnumRolesTest do
  # Roles kept as an Ecto.Enum in the app's table, as the RBAC guide shows.
  use SekishoTest.DataCase, async: true

  defmodule EnumMembership do
    use Ecto.Schema

    schema "memberships" do
      field :org_id, :id
      field :user_id, :id
      field :role, Ecto.Enum, values: [:member, :admin, :owner]
    end
  end

  defmodule EnumSources do
    use Sekisho.Sources
    import Ecto.Query

    @impl true
    def roles(SekishoTest.Org) do
      from m in EnumMembership,
        select: %{actor_id: m.user_id, resource_id: m.org_id, role: m.role}
    end
  end

  defmodule EnumPermissions do
    use Sekisho,
      repo: SekishoTest.Repo,
      policies: [SekishoTest.OrgPolicy, SekishoTest.FolderPolicy],
      sources: EnumSources

    @impl Sekisho
    def actor(%SekishoTest.Scope{user: user}), do: user
  end

  test "roles from an Ecto.Enum column" do
    org = insert!(%Org{name: "acme"})
    folder = insert!(%Folder{name: "f", org_id: org.id})
    admin = user!()
    insert!(%EnumMembership{org_id: org.id, user_id: admin.id, role: :admin})

    assert EnumPermissions.allowed?(scope(admin), :invite, org)
    refute EnumPermissions.allowed?(scope(admin), :manage, org)
    assert EnumPermissions.allowed?(scope(admin), :update, folder)
    assert Org |> EnumPermissions.where_allowed(scope(admin), :read) |> Repo.all() == [org]
    assert %{allowed?: true} = EnumPermissions.explain(scope(admin), :update, folder)
  end
end
