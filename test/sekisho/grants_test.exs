defmodule Sekisho.GrantsTest do
  # Granting and revoking: checked, kept to the policy's grant_to, broadcast.
  use SekishoTest.DataCase, async: true

  alias SekishoTest.{Membership, TeamMembership}

  setup do
    org = insert!(%Org{name: "acme"})
    folder = insert!(%Folder{name: "contracts", org_id: org.id})
    doc = insert!(%Document{title: "nda", org_id: org.id, folder_id: folder.id})
    owner = user!(name: "owner")
    {:ok, _} = Permissions.grant(nil, owner, :owner, on: doc, check: false)
    %{org: org, folder: folder, doc: doc, owner: owner}
  end

  test "an owner shares, and the grantee holds the role", %{doc: doc, owner: owner} do
    ana = user!()

    assert {:ok, %Sekisho.Grant{role: "editor", granted_by_id: granted_by}} =
             Permissions.grant(scope(owner), ana, :editor, on: doc)

    assert granted_by == owner.id
    assert Permissions.allowed?(scope(ana), :update, doc)
  end

  test "granting takes the permission grant_to names", %{doc: doc} do
    editor = user!()
    {:ok, _} = Permissions.grant(nil, editor, :editor, on: doc, check: false)

    assert {:error, %Sekisho.Denied{permission: :share}} =
             Permissions.grant(scope(editor), user!(), :viewer, on: doc)
  end

  test "no one gives a role above their own", %{org: org, folder: folder} do
    # An org's owner (from the sources) may manage it, but the org gives
    # roles through grant_to [:user], by: :manage only up to what they hold.
    owner = user!()
    insert!(%Membership{org_id: org.id, user_id: owner.id, role: "owner"})
    assert {:ok, _} = Permissions.grant(scope(owner), user!(), :admin, on: org)

    # A folder's sharer who is not its owner cannot make someone owner.
    sharer = user!()
    {:ok, _} = Permissions.grant(nil, sharer, :owner, on: folder, check: false)
    {:ok, _} = Permissions.revoke(nil, sharer, :owner, on: folder, check: false)
    refute Permissions.allowed?(scope(sharer), :share, folder)
  end

  test "a role that gives permissions the granter lacks is refused", %{doc: doc} do
    # Someone who may share (a rule could allow it) but holds no :delete.
    viewer = user!()
    {:ok, _} = Permissions.grant(nil, viewer, :viewer, on: doc, check: false)

    assert {:error, %Sekisho.Denied{}} =
             Permissions.grant(scope(viewer), user!(), :owner, on: doc)
  end

  test "grant_to: whom a policy grants to", %{org: org, doc: doc, owner: owner} do
    assert_raise ArgumentError, ~r/grants to \[:user\], not to a link/, fn ->
      Permissions.grant(nil, :link, :member, on: org, check: false)
    end

    assert_raise ArgumentError, ~r/grants a link up to :viewer, not :editor/, fn ->
      Permissions.grant(scope(owner), :link, :editor, on: doc)
    end

    assert {:ok, %{token: token}} = Permissions.grant(scope(owner), :link, :viewer, on: doc)
    assert is_binary(token)
  end

  test "an unknown role, a record not saved", %{doc: doc, owner: owner} do
    assert_raise ArgumentError, ~r/:boss is not a role of SekishoTest.DocumentPolicy/, fn ->
      Permissions.grant(scope(owner), user!(), :boss, on: doc)
    end

    assert_raise ArgumentError, ~r/on a record that is saved/, fn ->
      Permissions.grant(scope(owner), user!(), :viewer, on: %Document{})
    end
  end

  test "granting twice is one grant, with the latest expiry", %{doc: doc, owner: owner} do
    ana = user!()
    {:ok, first} = Permissions.grant(scope(owner), ana, :viewer, on: doc)
    later = DateTime.add(DateTime.utc_now(), 3600)
    {:ok, second} = Permissions.grant(scope(owner), ana, :viewer, on: doc, expires_at: later)

    assert first.id == second.id
    assert {:ok, grants} = Permissions.grants(scope(owner), doc)
    assert Enum.count(grants, &(&1.actor_id == ana.id)) == 1
  end

  test "revoke", %{doc: doc, owner: owner} do
    ana = user!()
    {:ok, _} = Permissions.grant(scope(owner), ana, :editor, on: doc)
    assert {:ok, 1} = Permissions.revoke(scope(owner), ana, :editor, on: doc)
    refute Permissions.allowed?(scope(ana), :read, doc)
    assert {:ok, 0} = Permissions.revoke(scope(owner), ana, :editor, on: doc)

    {:ok, %{token: token}} = Permissions.grant(scope(owner), :link, :viewer, on: doc)
    assert {:ok, 1} = Permissions.revoke(scope(owner), :link, :viewer, on: doc)
    refute Permissions.allowed?(scope(nil, [token]), :read, doc)
  end

  test "grants: who holds what, for those who may share", %{doc: doc, owner: owner} do
    team = insert!(%Team{name: "legal"})
    insert!(%TeamMembership{team_id: team.id, user_id: user!().id})
    {:ok, _} = Permissions.grant(scope(owner), team, :commenter, on: doc)

    assert {:ok,
            [%{actor_type: "users", role: "owner"}, %{actor_type: "teams", role: "commenter"}]} =
             Permissions.grants(scope(owner), doc)

    assert {:error, %Sekisho.Denied{permission: :share}} = Permissions.grants(scope(user!()), doc)
  end

  test "grants and revocations are broadcast", %{doc: doc, owner: owner} do
    Phoenix.PubSub.subscribe(SekishoTest.PubSub, "sekisho:documents:#{doc.id}")
    ana = user!()

    {:ok, _} = Permissions.grant(scope(owner), ana, :viewer, on: doc)

    assert_receive {:sekisho, :granted,
                    %{resource_type: "documents", actor_id: actor_id, role: "viewer"}}

    assert actor_id == ana.id

    {:ok, 1} = Permissions.revoke(scope(owner), ana, :viewer, on: doc)
    assert_receive {:sekisho, :revoked, %{role: "viewer"}}
  end
end
