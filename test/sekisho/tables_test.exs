defmodule Sekisho.TablesTest do
  # A library's permissions in its host's database: tables of its own
  # (tables: "library"), ids of its own type (uuid reports, bigint users),
  # and a repo it knows only at runtime (repo/0).
  use SekishoTest.DataCase, async: true

  alias Sekisho.Grant
  alias Sekisho.SQL.Dialect
  alias SekishoTest.{LibraryMigrations, LibraryPermissions, Report, TeamMembership}

  setup do
    owner = user!(name: "owner")
    report = insert!(%Report{title: "revenue"})
    {:ok, _} = LibraryPermissions.grant(nil, owner, :owner, on: report, check: false)
    %{owner: owner, report: report}
  end

  test "the tables are the library's, tracked apart, with ids of each type" do
    assert LibraryMigrations.migrated_version(repo: Repo) == 1
    assert Sekisho.Migrations.migrated_version(repo: Repo) == 1

    assert column_type("library_grants", "resource_id") == "uuid"
    assert column_type("library_grants", "actor_id") == "bigint"
    assert column_type("library_grants", "granted_by_id") == "bigint"
    assert column_type("library_roles", "resource_id") == "uuid"
    assert column_type("sekisho_grants", "resource_id") == "bigint"
  end

  test "a grant is kept in the library's tables, and checked from them", %{
    owner: owner,
    report: report
  } do
    ana = user!()
    refute LibraryPermissions.allowed?(scope(ana), :read, report)

    {:ok, grant} = LibraryPermissions.grant(scope(owner), ana, :editor, on: report)
    assert grant.__meta__.source == "library_grants"

    assert LibraryPermissions.allowed?(scope(ana), :read, report)
    assert LibraryPermissions.allowed?(scope(ana), :update, report)
    refute LibraryPermissions.allowed?(scope(ana), :manage, report)
    assert Report |> LibraryPermissions.where_allowed(scope(ana), :read) |> Repo.all() == [report]

    assert count("library_grants") == 2
    assert count("sekisho_grants") == 0

    # Granting again updates the grant, in the same table.
    later = DateTime.add(DateTime.utc_now(), 3600, :second)
    {:ok, _} = LibraryPermissions.grant(scope(owner), ana, :editor, on: report, expires_at: later)
    assert count("library_grants") == 2

    assert {:ok, 1} = LibraryPermissions.revoke(scope(owner), ana, :editor, on: report)
    refute LibraryPermissions.allowed?(scope(ana), :read, report)
  end

  test "a team and a link hold roles from the library's tables", %{
    owner: owner,
    report: report
  } do
    team = insert!(%Team{name: "finance"})
    ana = user!()
    insert!(%TeamMembership{team_id: team.id, user_id: ana.id})
    {:ok, _} = LibraryPermissions.grant(scope(owner), team, :viewer, on: report)
    assert LibraryPermissions.allowed?(scope(ana), :read, report)

    {:ok, link} = LibraryPermissions.grant(scope(owner), :link, :viewer, on: report)
    assert LibraryPermissions.allowed?(scope(nil, [link.token]), :read, report)
    refute LibraryPermissions.allowed?(scope(nil), :read, report)
  end

  test "a report's own roles, in the library's tables", %{owner: owner, report: report} do
    {:ok, role} = LibraryPermissions.create_role(scope(owner), report, "Reviewer", [:read])
    assert role.__meta__.source == "library_roles"
    assert count("sekisho_roles") == 0

    ana = user!()
    {:ok, _} = LibraryPermissions.grant(scope(owner), ana, "Reviewer", on: report)
    assert LibraryPermissions.allowed?(scope(ana), :read, report)

    assert %Sekisho.Explanation{allowed?: true, reasons: [{:grant, "Reviewer", _grant}]} =
             LibraryPermissions.explain(scope(ana), :read, report)

    {:ok, role} = LibraryPermissions.update_role(scope(owner), role, [:update])
    assert role.permissions == ["update"]
    refute LibraryPermissions.allowed?(scope(ana), :read, report)
    assert LibraryPermissions.allowed?(scope(ana), :update, report)

    assert {:ok, [%Sekisho.Role{name: "Reviewer"}]} =
             LibraryPermissions.roles(scope(owner), report)

    assert {:error, changeset} =
             LibraryPermissions.create_role(scope(owner), report, "Reviewer", [:read])

    assert {"is already a role of this record", _} = changeset.errors[:name]

    :ok = LibraryPermissions.delete_role(scope(owner), role)
    refute LibraryPermissions.allowed?(scope(ana), :update, report)
    assert count("library_role_permissions") == 0
  end

  test "the standard dialect upserts in the grant's own table", %{report: report} do
    ana = user!()

    grant =
      Ecto.put_meta(
        %Grant{
          resource_type: "reports",
          resource_id: report.id,
          actor_type: "users",
          actor_id: ana.id,
          role: "viewer"
        },
        source: "library_grants"
      )

    assert {:ok, first} = Dialect.Standard.upsert_grant(Repo, grant)
    assert {:ok, again} = Dialect.Standard.upsert_grant(Repo, grant)
    assert again.id == first.id
    assert count("library_grants") == 2
    assert count("sekisho_grants") == 0
  end

  defp count(table), do: Repo.aggregate(table, :count)

  defp column_type(table, column) do
    %{rows: [[type]]} =
      Repo.query!(
        "SELECT data_type FROM information_schema.columns WHERE table_name = $1 AND column_name = $2",
        [table, column]
      )

    type
  end
end
