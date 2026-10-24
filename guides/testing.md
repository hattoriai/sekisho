# Testing and explanations

## Assertions

```elixir
defmodule MyApp.PermissionsTest do
  use MyApp.DataCase, async: true
  use Sekisho.Test, permissions: MyApp.Permissions

  test "authors edit their own posts, and nothing locked" do
    ana = insert(:user)
    mine = insert(:post, author: ana)
    locked = insert(:post, author: ana, locked: true)

    assert_allowed scope(ana), :update, mine
    refute_allowed scope(ana), :update, locked
    assert_allowed scope(ana), :create, Post
  end

  test "readers see published posts and their own" do
    assert_where_allowed Post, scope(ana), :read, [mine, published]
  end
end
```

A failing assertion says why, with the explanation:

    expected to be allowed :update

    not allowed :update on MyApp.Blog.Post 12
      denied by a rule of the policy (deny/2)
      a rule of the policy (allow/2)

`assert_where_allowed/4` compares the ids, in any order, and names the
ones missing and the ones that should not be there.

## The policies together

Each policy checks itself when it compiles: a role that gives a
permission the policy does not have, a derive from a role that does not
exist. What crosses policies (a relation, a role of another schema, two
schemas that derive from each other) is checked the first time your
permissions module is asked, and by `validate!/0`. Have one test call it:

```elixir
test "the permissions are valid" do
  assert MyApp.Permissions.validate!() == :ok
end
```

## Explanations

`explain/3` gives every path that allows a permission on a record, and
whether a deny refuses it:

```elixir
iex> Permissions.explain(scope, :read, document)
#Sekisho.Explanation<allowed :read on MyApp.Drive.Document 7
  holds :editor through :folder: MyApp.Drive.Folder 3
    holds :editor through :parent: MyApp.Drive.Folder 1
      holds :editor: granted to users 5>
```

It is data too (`reasons`, `denied`), for a support page that answers
"why can Ana see this?":

```elixir
%Sekisho.Explanation{allowed?: true, reasons: [{:related, :editor, :folder, %Folder{}, [...]}]}
```

The reasons are `{:allow}`, `{:grant, role, grant}`, `{:source, role}`,
`{:related, role, relation, record, reasons}` and
`{:derived, permission, relation, record, reasons}`. An explanation runs
more queries than a check (it loads each record on the path), so it is for
a person reading, not for every request.

## Checks and lists agree

Sekisho's own tests build random worlds (folders nested at random, grants
to people, teams and links, roles each org defines, locked documents) and
check that `allowed?/3`, `where_allowed/3`, `with_permissions/3` and
`explain/3` give the same answer for every person, record and permission.
Your tests can rely on that, and test the rules, not the mechanism.
