defmodule Sekisho.CustomRolesTest do
  # Roles each org defines (custom_roles), and the permissions other
  # resources derive from the org's.
  use SekishoTest.DataCase, async: true

  alias SekishoTest.Membership

  setup do
    org = insert!(%Org{name: "acme"})
    owner = user!(name: "owner")
    insert!(%Membership{org_id: org.id, user_id: owner.id, role: "owner"})
    doc = insert!(%Document{title: "ledger", org_id: org.id})
    %{org: org, owner: owner, doc: doc}
  end

  test "an org's owner makes a role, grants it, and it gives its permissions", %{
    org: org,
    owner: owner,
    doc: doc
  } do
    {:ok, auditor} = Permissions.create_role(scope(owner), org, "Auditor", [:read, :audit])
    assert %Sekisho.Role{name: "Auditor", permissions: ["read", "audit"]} = auditor

    ana = user!()
    refute Permissions.allowed?(scope(ana), :audit, org)
    {:ok, _} = Permissions.grant(scope(owner), ana, "Auditor", on: org)

    assert Permissions.allowed?(scope(ana), :read, org)
    assert Permissions.allowed?(scope(ana), :audit, org)
    refute Permissions.allowed?(scope(ana), :invite, org)

    # Documents derive :read from the org's :audit.
    assert Permissions.allowed?(scope(ana), :read, doc)
    refute Permissions.allowed?(scope(ana), :update, doc)
    assert Document |> Permissions.where_allowed(scope(ana), :read) |> Repo.all() == [doc]
  end

  test "a permission from a role on the org", %{owner: owner, doc: doc} do
    assert Permissions.allowed?(scope(owner), :delete, doc)
    refute Permissions.allowed?(scope(user!()), :delete, doc)
  end

  test "changing a role changes what its holders may do", %{org: org, owner: owner, doc: doc} do
    {:ok, role} = Permissions.create_role(scope(owner), org, "Auditor", [:audit])
    ana = user!()
    {:ok, _} = Permissions.grant(scope(owner), ana, "Auditor", on: org)
    assert Permissions.allowed?(scope(ana), :read, doc)

    {:ok, role} = Permissions.update_role(scope(owner), role, [:invite])
    refute Permissions.allowed?(scope(ana), :read, doc)
    assert Permissions.allowed?(scope(ana), :invite, org)

    :ok = Permissions.delete_role(scope(owner), role)
    refute Permissions.allowed?(scope(ana), :invite, org)
    assert {:ok, []} = Permissions.roles(scope(owner), org)
    assert {:ok, grants} = Permissions.grants(scope(owner), org)
    refute Enum.any?(grants, &(&1.role == "Auditor"))
  end

  test "no one makes or grants a role above their own", %{org: org} do
    admin = user!()
    insert!(%Membership{org_id: org.id, user_id: admin.id, role: "admin"})

    # An admin may not :manage, so makes no role at all.
    assert {:error, %Sekisho.Denied{permission: :manage}} =
             Permissions.create_role(scope(admin), org, "Helper", [:read])

    # A manager without :audit (a custom role that manages) cannot give it.
    {:ok, _} = Permissions.create_role(nil, org, "Manager", [:manage, :read], check: false)
    manager = user!()
    {:ok, _} = Permissions.grant(nil, manager, "Manager", on: org, check: false)

    assert {:error, %Sekisho.Denied{permission: :audit}} =
             Permissions.create_role(scope(manager), org, "Auditor", [:audit])

    assert {:ok, _} = Permissions.create_role(scope(manager), org, "Reader", [:read])

    {:ok, auditor} = Permissions.create_role(nil, org, "Auditor", [:audit], check: false)

    assert {:error, %Sekisho.Denied{permission: :audit}} =
             Permissions.grant(scope(manager), user!(), "Auditor", on: org)

    assert {:error, %Sekisho.Denied{}} = Permissions.update_role(scope(manager), auditor, [:read])
  end

  test "names and permissions are checked", %{org: org, owner: owner} do
    assert_raise ArgumentError, ~r/"owner" is a role of SekishoTest.OrgPolicy already/, fn ->
      Permissions.create_role(scope(owner), org, "owner", [:read])
    end

    assert_raise ArgumentError, ~r/not blank/, fn ->
      Permissions.create_role(scope(owner), org, "  ", [:read])
    end

    assert_raise ArgumentError, ~r/:fly is not a permission of SekishoTest.OrgPolicy/, fn ->
      Permissions.create_role(scope(owner), org, "Pilot", [:fly])
    end

    # From a form: strings, only those declared.
    assert {:ok, %{permissions: ["read"]}} =
             Permissions.create_role(scope(owner), org, "Reader", ["read"])

    assert {:error, %Ecto.Changeset{errors: [name: {"is already a role of this record", _}]}} =
             Permissions.create_role(scope(owner), org, "Reader", [:read])

    assert_raise ArgumentError, ~r/"Ghost" is not a role of/, fn ->
      Permissions.grant(scope(owner), user!(), "Ghost", on: org)
    end
  end

  test "a role of one org is not another's", %{org: org, owner: owner} do
    other = insert!(%Org{name: "other"})
    {:ok, _} = Permissions.create_role(scope(owner), org, "Auditor", [:audit])

    assert_raise ArgumentError, ~r/"Auditor" is not a role of/, fn ->
      Permissions.grant(nil, user!(), "Auditor", on: other, check: false)
    end
  end

  test "a policy without custom_roles has none", %{doc: doc} do
    assert_raise ArgumentError, ~r/SekishoTest.DocumentPolicy has no custom_roles/, fn ->
      Permissions.create_role(nil, doc, "Editor-in-chief", [:update], check: false)
    end
  end

  test "explain names the custom role and the permission derived from it", %{
    org: org,
    owner: owner,
    doc: doc
  } do
    {:ok, _} = Permissions.create_role(scope(owner), org, "Auditor", [:audit])
    ana = user!()
    {:ok, _} = Permissions.grant(scope(owner), ana, "Auditor", on: org)

    explanation = Permissions.explain(scope(ana), :read, doc)

    assert %{allowed?: true, reasons: [{:derived, :read, :org, %Org{}, [{:grant, "Auditor", _}]}]} =
             explanation

    assert Sekisho.Explanation.lines(explanation) == [
             "allowed :read on SekishoTest.Document #{doc.id}",
             "  has :read through :org: SekishoTest.Org #{org.id}",
             "    holds \"Auditor\": granted to users #{ana.id}"
           ]
  end

  test "role changes are broadcast", %{org: org, owner: owner} do
    Phoenix.PubSub.subscribe(SekishoTest.PubSub, "sekisho:orgs:#{org.id}")
    {:ok, _} = Permissions.create_role(scope(owner), org, "Auditor", [:audit])
    assert_receive {:sekisho, :role_changed, %{role: "Auditor"}}
  end
end
