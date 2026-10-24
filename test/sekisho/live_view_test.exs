defmodule Sekisho.LiveViewTest do
  # The hook: events checked before handle_event/3, and a page that loses its
  # access while it is open.
  use SekishoTest.DataCase, async: false
  use PhoenixMountable.Test, host: SekishoTest.Host

  alias SekishoTest.Membership

  setup do
    org = insert!(%Org{name: "acme"})
    doc = insert!(%Document{title: "Contract", org_id: org.id})
    ana = user!(name: "ana")
    {:ok, _} = Permissions.grant(nil, ana, :viewer, on: doc, check: false)
    conn = Plug.Test.init_test_session(build_conn(), user_id: ana.id)
    %{org: org, doc: doc, ana: ana, conn: conn}
  end

  test "an event the scope may not do is refused before handle_event", %{conn: conn, doc: doc} do
    {:ok, view, html} = live(conn, "/documents/#{doc.id}")
    assert html =~ "Contract"

    html = render_click(view, "delete")
    assert html =~ "You are not allowed to do that."
    refute html =~ "Deleted"

    # Events not in the map are the page's own.
    render_click(view, "ping")
  end

  test "an event the scope may do goes through", %{conn: conn, doc: doc, org: org, ana: ana} do
    insert!(%Membership{org_id: org.id, user_id: ana.id, role: "owner"})
    {:ok, view, _html} = live(conn, "/documents/#{doc.id}")
    assert render_click(view, "delete") =~ "Deleted"
  end

  test "a revoked grant sends the open page away", %{conn: conn, doc: doc, ana: ana} do
    {:ok, view, _html} = live(conn, "/documents/#{doc.id}")
    {:ok, 1} = Permissions.revoke(nil, ana, :viewer, on: doc, check: false)

    assert_redirect(view, "/")
  end

  test "a change in the app's own tables, told with changed/0", %{doc: doc, org: org} do
    bruno = user!(name: "bruno")
    membership = insert!(%Membership{org_id: org.id, user_id: bruno.id, role: "admin"})
    conn = Plug.Test.init_test_session(build_conn(), user_id: bruno.id)
    {:ok, view, _html} = live(conn, "/documents/#{doc.id}")

    # Another grant changes nothing for this page.
    {:ok, _} = Permissions.grant(nil, user!(), :viewer, on: doc, check: false)
    assert render(view) =~ "Contract"

    Repo.delete!(membership)
    :ok = Permissions.changed()
    assert_redirect(view, "/")
  end
end
