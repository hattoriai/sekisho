defmodule Sekisho.ExplainTest do
  use SekishoTest.DataCase, async: true

  alias SekishoTest.Membership

  test "the path from a grant on an ancestor folder" do
    org = insert!(%Org{name: "acme"})
    root = insert!(%Folder{name: "root", org_id: org.id})
    leaf = insert!(%Folder{name: "leaf", org_id: org.id, parent_id: root.id})
    doc = insert!(%Document{title: "nda", org_id: org.id, folder_id: leaf.id})
    ana = user!()
    {:ok, _} = Permissions.grant(nil, ana, :editor, on: root, check: false)

    explanation = Permissions.explain(scope(ana), :read, doc)
    assert explanation.allowed?

    assert [
             {:related, :editor, :folder, %Folder{},
              [{:related, :editor, :parent, %Folder{}, [{:grant, :editor, _}]}]}
           ] =
             explanation.reasons

    assert Sekisho.Explanation.lines(explanation) == [
             "allowed :read on SekishoTest.Document #{doc.id}",
             "  holds :editor through :folder: SekishoTest.Folder #{leaf.id}",
             "    holds :editor through :parent: SekishoTest.Folder #{root.id}",
             "      holds :editor: granted to users #{ana.id}"
           ]
  end

  test "an org admin, a rule, a deny, nothing" do
    org = insert!(%Org{name: "acme"})
    admin = user!()
    insert!(%Membership{org_id: org.id, user_id: admin.id, role: "admin"})
    author = user!()
    doc = insert!(%Document{title: "nda", org_id: org.id, author_id: author.id, locked: true})

    assert %{allowed?: false, denied: true} = Permissions.explain(scope(admin), :update, doc)

    assert %{allowed?: true, reasons: [{:related, :editor, :org, %Org{}, [{:source, :admin}]}]} =
             Permissions.explain(scope(admin), :comment, doc)

    assert %{allowed?: true, reasons: [{:allow}]} = Permissions.explain(scope(author), :read, doc)

    nobody = Permissions.explain(scope(user!()), :read, doc)
    assert %{allowed?: false, reasons: []} = nobody
    assert Sekisho.Explanation.lines(nobody) |> List.last() =~ "no rule allows it"
    assert inspect(nobody) =~ "#Sekisho.Explanation<not allowed :read"
  end
end
