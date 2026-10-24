defmodule Sekisho.FieldsTest do
  use SekishoTest.DataCase, async: true

  test "the fields an actor may see, and the record without the others" do
    author = user!()
    admin = user!(admin: true)
    doc = insert!(%Document{title: "nda", contract_value: 90_000, author_id: author.id})

    assert :contract_value in Permissions.allowed_fields(scope(author), doc)
    assert :contract_value in Permissions.allowed_fields(scope(admin), doc)
    refute :contract_value in Permissions.allowed_fields(scope(user!()), doc)

    assert %{contract_value: 90_000} = Permissions.redact(scope(author), doc)
    assert %{id: id, title: "nda", contract_value: nil} = Permissions.redact(scope(nil), doc)
    assert id == doc.id
  end

  test "a policy without allow_fields shows every field" do
    post = insert!(%Post{title: "hello"})
    assert Permissions.allowed_fields(scope(nil), post) == Post.__schema__(:fields)
  end
end
