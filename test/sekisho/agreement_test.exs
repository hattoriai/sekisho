defmodule Sekisho.AgreementTest do
  # For random data, the three answers agree for every actor, record and
  # permission: a check (allowed?/3), a list (where_allowed/3), one query for
  # many (with_permissions/3) and an explanation (explain/3).
  use SekishoTest.DataCase, async: true

  alias SekishoTest.{Membership, TeamMembership}

  @permissions [:read, :comment, :update, :share, :delete]

  for seed <- 1..12 do
    @tag seed: seed
    test "random data #{seed}", %{seed: seed} do
      :rand.seed(:exsss, {seed, seed * 7, seed * 13})
      {users, docs, tokens} = world()

      for user <- [nil | users], permission <- @permissions do
        scope = scope(user, if(user, do: [], else: tokens))

        listed =
          Document
          |> Permissions.where_allowed(scope, permission)
          |> Repo.all()
          |> MapSet.new(& &1.id)

        many = Permissions.with_permissions(docs, scope, [permission])

        for {doc, held} <- many do
          allowed = Permissions.allowed?(scope, permission, doc)
          explained = Permissions.explain(scope, permission, doc).allowed?
          who = if user, do: user.id, else: :visitor

          assert allowed == MapSet.member?(listed, doc.id), "list: #{who} #{permission} #{doc.id}"
          assert allowed == permission in held, "with_permissions: #{who} #{permission} #{doc.id}"
          assert allowed == explained, "explain: #{who} #{permission} #{doc.id}"
        end
      end
    end
  end

  # Orgs with members, a forest of folders, documents in them, grants to
  # users, teams and links on folders and documents.
  defp world do
    users = for i <- 1..5, do: user!(name: "u#{i}", admin: i == 5)
    orgs = for i <- 1..2, do: insert!(%Org{name: "org#{i}"})
    teams = for i <- 1..2, do: insert!(%Team{name: "team#{i}"})
    members!(users, orgs, teams)

    folders = folders!(orgs)
    docs = for i <- 1..10, do: document!(i, folders, orgs, users)

    for _ <- 1..14 do
      role = Enum.random([:viewer, :commenter, :editor, :owner])

      {:ok, _} =
        Permissions.grant(nil, Enum.random(users ++ teams), role,
          on: Enum.random(folders ++ docs),
          check: false
        )
    end

    for org <- orgs, i <- 1..2 do
      permissions = Enum.take_random([:read, :invite, :audit], :rand.uniform(2))
      {:ok, _} = Permissions.create_role(nil, org, "custom#{i}", permissions, check: false)
      user = Enum.random(users)
      {:ok, _} = Permissions.grant(nil, user, "custom#{i}", on: org, check: false)
    end

    tokens = for _ <- 1..3, do: link!(Enum.random(folders ++ docs))
    {users, docs, tokens}
  end

  defp members!(users, orgs, teams) do
    for user <- users, org <- orgs, :rand.uniform(3) == 1 do
      insert!(%Membership{
        org_id: org.id,
        user_id: user.id,
        role: Enum.random(~w(member admin owner))
      })
    end

    for user <- users, team <- teams, :rand.uniform(3) == 1 do
      insert!(%TeamMembership{team_id: team.id, user_id: user.id})
    end
  end

  defp folders!(orgs) do
    Enum.reduce(1..8, [], fn i, folders ->
      parent = if folders != [] and :rand.uniform(3) > 1, do: Enum.random(folders)
      org_id = if parent, do: parent.org_id, else: Enum.random(orgs).id
      [insert!(%Folder{name: "f#{i}", org_id: org_id, parent_id: parent && parent.id}) | folders]
    end)
  end

  defp document!(i, folders, orgs, users) do
    folder = Enum.random([nil | folders])

    insert!(%Document{
      title: "d#{i}",
      org_id: if(folder, do: folder.org_id, else: Enum.random(orgs).id),
      folder_id: folder && folder.id,
      author_id: if(:rand.uniform(4) == 1, do: Enum.random(users).id),
      locked: :rand.uniform(4) == 1
    })
  end

  defp link!(%Folder{} = folder), do: token!(folder, Enum.random([:viewer, :commenter]))
  defp link!(document), do: token!(document, :viewer)

  defp token!(record, role) do
    {:ok, %{token: token}} = Permissions.grant(nil, :link, role, on: record, check: false)
    token
  end
end
