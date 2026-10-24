# Quickstart

This guide builds the permissions of a small app, one step at a time: a
blog where people write posts, then orgs whose members share documents.
It assumes Sekisho is installed (see the README) and that your app has
Phoenix 1.8's `%Scope{}` from `mix phx.gen.auth`.

## 1. The permissions module

The installer wrote `lib/my_app/permissions.ex`:

```elixir
defmodule MyApp.Permissions do
  use Sekisho,
    repo: MyApp.Repo,
    pubsub: MyApp.PubSub,
    policies: []

  @impl Sekisho
  def actor(%MyApp.Accounts.Scope{user: user}), do: user
  def actor(nil), do: nil
end
```

Every question goes through this module, with your scope first, as your
contexts take it. `actor/1` turns the scope into the person asking: a
user, or `nil` for a visitor.

## 2. A rule

A policy holds the rules of one schema:

```elixir
defmodule MyApp.Blog.PostPolicy do
  use Sekisho.Policy, for: MyApp.Blog.Post
  import Ecto.Query

  alias MyApp.Accounts.User

  permissions [:read, :create, :update, :delete]

  @impl true
  def allow(%User{id: id}, :read), do: dynamic([p], p.published or p.author_id == ^id)
  def allow(%User{id: id}, permission) when permission in [:update, :delete],
    do: dynamic([p], p.author_id == ^id)
  def allow(%User{}, :create), do: true
  def allow(nil, :read), do: dynamic([p], p.published)
end
```

Add it to the module:

```elixir
policies: [MyApp.Blog.PostPolicy]
```

`allow/2` answers with `true` (everywhere), `false` (nowhere), or a
condition on the record. A permission no clause matches is not allowed,
so there is no last clause to write.

## 3. Ask

In the context:

```elixir
def get_post!(scope, id) do
  post = Repo.get!(Post, id)
  :ok = Permissions.authorize!(scope, :read, post)
  post
end

def update_post(scope, post, attrs) do
  with :ok <- Permissions.authorize(scope, :update, post) do
    post |> Post.changeset(attrs) |> Repo.update()
  end
end

def list_posts(scope) do
  Post
  |> Permissions.where_allowed(scope, :read)
  |> order_by(desc: :inserted_at)
  |> Repo.all()
end
```

`where_allowed/3` takes your query and adds the condition, so it composes
with your own `where`, `order_by` and pagination. The list and the check
come from the same `allow/2`: a post is in the list exactly when
`allowed?/3` says yes.

In a template, `allowed?/3` (imported by the installer):

```heex
<.button :if={allowed?(@current_scope, :delete, @post)} phx-click="delete">Delete</.button>
```

For a list with buttons on each row, ask once for every row:

```elixir
rows = Permissions.with_permissions(posts, scope, [:update, :delete])
# [{%Post{}, [:update, :delete]}, {%Post{}, []}, ...]
```

## 4. Roles

Orgs have members, and members have roles. Your app already keeps them,
in a `memberships` table. Tell Sekisho where they are, in a sources
module:

```elixir
defmodule MyApp.Permissions.Sources do
  use Sekisho.Sources
  import Ecto.Query

  @impl true
  def roles(MyApp.Orgs.Org) do
    from m in MyApp.Orgs.Membership,
      select: %{actor_id: m.user_id, resource_id: m.org_id, role: m.role}
  end
end
```

and add `sources: MyApp.Permissions.Sources` to `use Sekisho`. Then the
org's policy says what each role gives:

```elixir
defmodule MyApp.Orgs.OrgPolicy do
  use Sekisho.Policy, for: MyApp.Orgs.Org

  permissions [:read, :invite, :manage]

  role :member, permissions: [:read]
  role :admin, permissions: [:invite]
  role :owner, permissions: :all

  derive :member, from: :admin
  derive :admin, from: :owner
end
```

`derive :member, from: :admin` says admins are members too, so an admin
may `:read` and `:invite`.

## 5. Shared documents

Documents belong to an org and sit in folders. People share them with
each other:

```elixir
defmodule MyApp.Docs.DocumentPolicy do
  use Sekisho.Policy, for: MyApp.Docs.Document

  permissions [:read, :comment, :update, :share, :delete]

  role :viewer, permissions: [:read]
  role :commenter, permissions: [:comment]
  role :editor, permissions: [:update]
  role :owner, permissions: [:share, :delete]

  derive :commenter, from: :editor
  derive :viewer, from: :commenter
  derive :editor, from: :owner

  # An org's admins edit its documents.
  derive :editor, from: {:org, :admin}

  grant_to [:user, :link], link_up_to: :viewer
end
```

`{:org, :admin}` follows the document's `belongs_to :org`: whoever is an
admin of that org is an editor of the document. Now share one:

```elixir
{:ok, _} = Permissions.grant(scope, ana, :editor, on: document)
{:ok, %{token: token}} = Permissions.grant(scope, :link, :viewer, on: document)
```

Granting is checked too: it takes `:share`, and no one gives a role above
their own. A visitor who follows the link shows its token in your scope
(`link_tokens/1` of the permissions module), and may then read it.

The [Sharing and relations](rebac.md) guide adds folders, nested to any
depth, and teams.

## 6. A LiveView

Add the hook to your `live_session`, after the one that sets the scope:

```elixir
live_session :app,
  on_mount: [
    {MyAppWeb.UserAuth, :require_authenticated},
    {Sekisho.LiveView, MyApp.Permissions}
  ] do
  live "/documents/:id", DocumentLive
end
```

and say what the page needs:

```elixir
def mount(%{"id" => id}, _session, socket) do
  document = Docs.get_document!(socket.assigns.current_scope, id)

  {:ok,
   socket
   |> assign(document: document)
   |> Sekisho.LiveView.watch(:read, document)
   |> Sekisho.LiveView.authorize_events(%{"delete" => {:delete, :document}})}
end
```

A `"delete"` event from someone who may not delete never reaches your
`handle_event/3`. And if Ana's access is revoked while she has the
document open, her page goes away, with a flash.

## 7. Test it

```elixir
use Sekisho.Test, permissions: MyApp.Permissions

test "authors edit their own posts" do
  assert_allowed scope(ana), :update, anas_post
  refute_allowed scope(ana), :update, brunos_post
  assert_where_allowed Post, scope(ana), :read, [anas_post, published_post]
end

test "the permissions are valid" do
  assert MyApp.Permissions.validate!() == :ok
end
```

A failing assertion prints why, from `explain/3`.

Next: [Rules](rules.md), [Role-based access](rbac.md),
[Sharing and relations](rebac.md).
