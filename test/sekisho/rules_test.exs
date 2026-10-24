defmodule Sekisho.RulesTest do
  # Level 1: rules only (SekishoTest.PostPolicy), no roles.
  use SekishoTest.DataCase, async: true

  setup do
    ana = user!(name: "ana")
    bruno = user!(name: "bruno")
    admin = user!(name: "admin", admin: true)

    draft = insert!(%Post{title: "draft", author_id: ana.id})
    published = insert!(%Post{title: "published", author_id: ana.id, published: true})
    locked = insert!(%Post{title: "locked", author_id: ana.id, locked: true})

    %{ana: ana, bruno: bruno, admin: admin, draft: draft, published: published, locked: locked}
  end

  test "a condition on the record, checked in the database", %{ana: ana, bruno: bruno} = ctx do
    assert Permissions.allowed?(scope(ana), :read, ctx.draft)
    assert Permissions.allowed?(scope(ana), :update, ctx.draft)
    refute Permissions.allowed?(scope(bruno), :read, ctx.draft)
    assert Permissions.allowed?(scope(bruno), :read, ctx.published)
    refute Permissions.allowed?(scope(bruno), :update, ctx.published)
  end

  test "deny wins, even for an admin", %{ana: ana, admin: admin} = ctx do
    refute Permissions.allowed?(scope(ana), :update, ctx.locked)
    refute Permissions.allowed?(scope(admin), :update, ctx.locked)
    assert Permissions.allowed?(scope(admin), :delete, ctx.locked)
  end

  test "a visitor is nil", ctx do
    assert Permissions.allowed?(scope(nil), :read, ctx.published)
    refute Permissions.allowed?(scope(nil), :read, ctx.draft)
    refute Permissions.allowed?(nil, :create, Post)
  end

  test "a rule about the actor alone needs no record", %{ana: ana} do
    assert Permissions.allowed?(scope(ana), :create, Post)
    assert Permissions.allowed?(scope(ana), :create, %Post{})
  end

  test "a rule about the record needs one", %{ana: ana} do
    assert_raise ArgumentError, ~r/depends on the record/, fn ->
      Permissions.allowed?(scope(ana), :update, Post)
    end
  end

  test "a permission the policy does not have is an error", %{ana: ana, draft: draft} do
    assert_raise ArgumentError, ~r/:publish is not a permission of SekishoTest.PostPolicy/, fn ->
      Permissions.allowed?(scope(ana), :publish, draft)
    end
  end

  test "lists from the same rules", %{ana: ana, bruno: bruno, admin: admin} do
    titles = fn scope, permission ->
      Post
      |> Permissions.where_allowed(scope, permission)
      |> Repo.all()
      |> Enum.map(& &1.title)
      |> Enum.sort()
    end

    assert titles.(scope(ana), :read) == ["draft", "locked", "published"]
    assert titles.(scope(ana), :update) == ["draft", "published"]
    assert titles.(scope(bruno), :read) == ["published"]
    assert titles.(scope(bruno), :update) == []
    assert titles.(scope(nil), :read) == ["published"]
    assert titles.(scope(admin), :update) == ["draft", "published"]
  end

  test "where_allowed composes with the app's own query", %{bruno: bruno} do
    import Ecto.Query

    query = from p in Post, where: p.title != "nothing", order_by: p.title

    assert [%Post{title: "published"}] =
             query |> Permissions.where_allowed(scope(bruno), :read) |> Repo.all()
  end

  test "authorize and authorize!", %{bruno: bruno, draft: draft, published: published} do
    assert :ok = Permissions.authorize(scope(bruno), :read, published)

    assert {:error, %Sekisho.Denied{permission: :read, resource: ^draft, plug_status: 403}} =
             Permissions.authorize(scope(bruno), :read, draft)

    error =
      assert_raise Sekisho.Denied, fn -> Permissions.authorize!(scope(bruno), :read, draft) end

    assert Exception.message(error) == "not allowed to :read SekishoTest.Post #{draft.id}"
  end

  test "with_permissions: every record's permissions in one query",
       %{ana: ana, bruno: bruno} = ctx do
    posts = [ctx.draft, ctx.published, ctx.locked]

    assert [
             {_, [:read, :update, :delete]},
             {_, [:read, :update, :delete]},
             {_, [:read, :delete]}
           ] = Permissions.with_permissions(posts, scope(ana), [:read, :update, :delete])

    assert [{_, []}, {_, [:read]}, {_, []}] =
             Permissions.with_permissions(posts, scope(bruno), [:read, :update, :delete])

    assert Permissions.with_permissions([], scope(bruno), [:read]) == []
  end

  test "each decision is told to telemetry", %{bruno: bruno, published: published} do
    ref = :telemetry_test.attach_event_handlers(self(), [[:sekisho, :decision]])
    Permissions.allowed?(scope(bruno), :read, published)

    assert_receive {[:sekisho, :decision], ^ref, %{},
                    %{permission: :read, schema: Post, allowed: true, root: Permissions}}
  end
end
