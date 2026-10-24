defmodule Sekisho.RolesTest do
  # Roles held through grants, sources, groups and links, derived on the same
  # record, across relations and down nested folders.
  use SekishoTest.DataCase, async: true

  alias SekishoTest.{Membership, ProjectDocument, Review, TeamMembership}

  setup do
    org = insert!(%Org{name: "acme"})
    root = insert!(%Folder{name: "root", org_id: org.id})
    mid = insert!(%Folder{name: "mid", org_id: org.id, parent_id: root.id})
    leaf = insert!(%Folder{name: "leaf", org_id: org.id, parent_id: mid.id})
    other = insert!(%Folder{name: "other", org_id: org.id})

    doc = insert!(%Document{title: "in leaf", org_id: org.id, folder_id: leaf.id})
    elsewhere = insert!(%Document{title: "in other", org_id: org.id, folder_id: other.id})

    %{org: org, root: root, mid: mid, leaf: leaf, other: other, doc: doc, elsewhere: elsewhere}
  end

  defp grant!(to, role, record),
    do: {:ok, _} = Permissions.grant(nil, to, role, on: record, check: false)

  defp titles(scope, permission) do
    Document
    |> Permissions.where_allowed(scope, permission)
    |> Repo.all()
    |> Enum.map(& &1.title)
    |> Enum.sort()
  end

  describe "roles from the app's own tables (sources)" do
    test "an org's roles, and those they derive", %{org: org} do
      member = user!()
      admin = user!()
      owner = user!()
      insert!(%Membership{org_id: org.id, user_id: member.id, role: "member"})
      insert!(%Membership{org_id: org.id, user_id: admin.id, role: "admin"})
      insert!(%Membership{org_id: org.id, user_id: owner.id, role: "owner"})

      assert Permissions.allowed?(scope(member), :read, org)
      refute Permissions.allowed?(scope(member), :invite, org)
      assert Permissions.allowed?(scope(admin), :read, org)
      assert Permissions.allowed?(scope(admin), :invite, org)
      refute Permissions.allowed?(scope(admin), :manage, org)
      assert Permissions.allowed?(scope(owner), :manage, org)
      refute Permissions.allowed?(scope(user!()), :read, org)
    end

    test "an org's admins edit its folders and documents", %{org: org} = ctx do
      admin = user!()
      insert!(%Membership{org_id: org.id, user_id: admin.id, role: "admin"})

      assert Permissions.allowed?(scope(admin), :update, ctx.leaf)
      assert Permissions.allowed?(scope(admin), :update, ctx.doc)
      refute Permissions.allowed?(scope(admin), :delete, ctx.doc)
      assert titles(scope(admin), :update) == ["in leaf", "in other"]
    end

    test "an open review makes its reviewer an editor", %{doc: doc} do
      reviewer = user!()
      review = insert!(%Review{document_id: doc.id, reviewer_id: reviewer.id})

      assert Permissions.allowed?(scope(reviewer), :update, doc)
      assert titles(scope(reviewer), :read) == ["in leaf"]

      Repo.update!(Ecto.Changeset.change(review, state: "closed"))
      refute Permissions.allowed?(scope(reviewer), :read, doc)
    end

    test "a relation that is not a belongs_to: a project's members see its documents", %{doc: doc} do
      project = insert!(%Project{name: "launch"})
      insert!(%ProjectDocument{project_id: project.id, document_id: doc.id})
      member = user!()
      grant!(member, :member, project)

      assert Permissions.allowed?(scope(member), :read, doc)
      refute Permissions.allowed?(scope(member), :update, doc)
      assert titles(scope(member), :read) == ["in leaf"]
    end
  end

  describe "nested folders" do
    test "a role on a folder reaches every folder and document under it", ctx do
      ana = user!()
      grant!(ana, :viewer, ctx.root)

      for folder <- [ctx.root, ctx.mid, ctx.leaf],
          do: assert(Permissions.allowed?(scope(ana), :read, folder))

      refute Permissions.allowed?(scope(ana), :read, ctx.other)
      assert Permissions.allowed?(scope(ana), :read, ctx.doc)
      refute Permissions.allowed?(scope(ana), :comment, ctx.doc)
      assert titles(scope(ana), :read) == ["in leaf"]
    end

    test "only down, never up", ctx do
      ana = user!()
      grant!(ana, :editor, ctx.mid)

      refute Permissions.allowed?(scope(ana), :read, ctx.root)
      assert Permissions.allowed?(scope(ana), :update, ctx.leaf)
      assert Permissions.allowed?(scope(ana), :update, ctx.doc)
    end

    test "an owner of a parent is an owner under it, and owners are editors", ctx do
      ana = user!()
      grant!(ana, :owner, ctx.root)

      assert Permissions.allowed?(scope(ana), :share, ctx.doc)
      assert Permissions.allowed?(scope(ana), :update, ctx.doc)
      assert Permissions.allowed?(scope(ana), :read, ctx.doc)
    end

    test "a loop in the data ends", ctx do
      Repo.update!(Ecto.Changeset.change(ctx.root, parent_id: ctx.leaf.id))
      ana = user!()
      grant!(ana, :viewer, ctx.mid)

      assert Permissions.allowed?(scope(ana), :read, ctx.root)
      assert titles(scope(ana), :read) == ["in leaf"]
    end
  end

  describe "rules and roles together" do
    test "deny wins over a role", ctx do
      ana = user!()
      grant!(ana, :editor, ctx.doc)
      assert Permissions.allowed?(scope(ana), :update, ctx.doc)

      locked = Repo.update!(Ecto.Changeset.change(ctx.doc, locked: true))
      refute Permissions.allowed?(scope(ana), :update, locked)
      assert Permissions.allowed?(scope(ana), :comment, locked)
    end

    test "a rule or a role allows", ctx do
      author = user!()
      mine = insert!(%Document{title: "mine", org_id: ctx.org.id, author_id: author.id})
      grant!(author, :viewer, ctx.doc)

      assert titles(scope(author), :read) == ["in leaf", "mine"]
      assert titles(scope(author), :update) == ["mine"]
      assert Permissions.allowed?(scope(author), :delete, mine)
    end
  end

  describe "who holds a grant" do
    test "a group's members", ctx do
      team = insert!(%Team{name: "design"})
      ana = user!()
      insert!(%TeamMembership{team_id: team.id, user_id: ana.id})
      grant!(team, :viewer, ctx.other)

      assert Permissions.allowed?(scope(ana), :read, ctx.elsewhere)
      refute Permissions.allowed?(scope(user!()), :read, ctx.elsewhere)
      assert titles(scope(ana), :read) == ["in other"]
    end

    test "anyone with a link", ctx do
      {:ok, grant} = Permissions.grant(nil, :link, :viewer, on: ctx.doc, check: false)
      assert is_binary(grant.token)

      assert Permissions.allowed?(scope(nil, [grant.token]), :read, ctx.doc)
      assert Permissions.allowed?(scope(user!(), [grant.token]), :read, ctx.doc)
      refute Permissions.allowed?(scope(nil, ["guess"]), :read, ctx.doc)
      refute Permissions.allowed?(scope(nil, [grant.token]), :update, ctx.doc)
      assert titles(scope(nil, [grant.token]), :read) == ["in leaf"]
    end

    test "a grant that expired", ctx do
      ana = user!()
      past = DateTime.add(DateTime.utc_now(), -60)
      future = DateTime.add(DateTime.utc_now(), 3600)

      {:ok, _} = Permissions.grant(nil, ana, :viewer, on: ctx.doc, check: false, expires_at: past)
      refute Permissions.allowed?(scope(ana), :read, ctx.doc)

      {:ok, _} =
        Permissions.grant(nil, ana, :viewer, on: ctx.doc, check: false, expires_at: future)

      assert Permissions.allowed?(scope(ana), :read, ctx.doc)
    end
  end

  test "many documents, one query for their buttons", ctx do
    ana = user!()
    grant!(ana, :editor, ctx.leaf)
    grant!(ana, :viewer, ctx.other)

    assert [{_, [:read, :comment, :update]}, {_, [:read]}] =
             Permissions.with_permissions([ctx.doc, ctx.elsewhere], scope(ana), [
               :read,
               :comment,
               :update,
               :delete
             ])
  end
end
