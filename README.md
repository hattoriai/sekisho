# Sekisho

![Sekisho — Permissions for Phoenix](https://raw.githubusercontent.com/hattoriai/sekisho/main/media/banner.png)

<p>
  <a href="https://hex.pm/packages/sekisho">
    <img alt="Hex Version" src="https://img.shields.io/hexpm/v/sekisho.svg">
  </a>
  <a href="https://hexdocs.pm/sekisho">
    <img src="https://img.shields.io/badge/docs-hexdocs-blue" alt="HexDocs">
  </a>
  <a href="https://github.com/hattoriai/sekisho/actions">
    <img alt="CI Status" src="https://github.com/hattoriai/sekisho/actions/workflows/ci.yml/badge.svg">
  </a>
</p>

**Permissions for Phoenix: who may do what, from one rule on a post to
roles each customer defines and documents shared like Google Docs.**

An author edits their own posts. An org's admins manage its members, with
roles the org makes for itself. A folder is shared with a person, a team,
or anyone with the link, and everything inside it comes along. You write
each rule once, in Elixir, and the same rule answers "may Ana edit this?"
and "which documents may Ana see?", the second one in your database.

Sekisho (関所) were the checkpoints on the roads of Edo Japan, where guards
checked each traveller's pass. Sekisho keeps its grants in your own
database, next to your data, and needs no other service.

## Install

You need Elixir 1.18+, Ecto 3.13 on a SQL database (PostgreSQL, MySQL
or MariaDB, SQLite, or another through a
[dialect](https://hexdocs.pm/sekisho/Sekisho.SQL.Dialect.html)), and Phoenix
1.7.14 or 1.8. LiveView is optional.

With [Igniter](https://hexdocs.pm/igniter), one command adds Sekisho and
sets it up. It shows each change and asks before it writes:

```sh
mix igniter.install sekisho
mix ecto.migrate
```

<details>
<summary>Without Igniter</summary>

Add `{:sekisho, "~> 0.2"}` to the deps in `mix.exs`, then run:

```sh
mix deps.get
mix sekisho.gen.migration
mix ecto.migrate
```

Write your permissions module in `lib/my_app/permissions.ex`:

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

Import `allowed?/3` in the `html_helpers` of `lib/my_app_web.ex`, for
your templates:

```elixir
import MyApp.Permissions, only: [allowed?: 3]
```

And add `:sekisho` to the `import_deps` of `.formatter.exs`, so policies
read `role :viewer, permissions: [:read]`.

</details>

## Your first policy

A policy holds the rules of one schema. Each rule is a function that
takes the person asking and a permission, and returns `true`, `false`, or
a condition on the record, written with `Ecto.Query.dynamic/2`:

```elixir
defmodule MyApp.Blog.PostPolicy do
  use Sekisho.Policy, for: MyApp.Blog.Post
  import Ecto.Query

  alias MyApp.Accounts.User

  permissions [:read, :create, :update, :delete]

  @impl true
  def allow(%User{admin: true}, _permission), do: true
  def allow(%User{id: id}, :read), do: dynamic([p], p.published or p.author_id == ^id)
  def allow(%User{id: id}, :update), do: dynamic([p], p.author_id == ^id)
  def allow(%User{}, :create), do: true
  def allow(nil, :read), do: dynamic([p], p.published)

  @impl true
  def deny(_user, :update), do: dynamic([p], p.locked)
end
```

Add it to the `policies:` of your permissions module. Then ask, with
your scope first:

```elixir
def update_post(scope, post, attrs) do
  with :ok <- Permissions.authorize(scope, :update, post) do
    post |> Post.changeset(attrs) |> Repo.update()
  end
end

def list_posts(scope) do
  Post |> Permissions.where_allowed(scope, :read) |> Repo.all()
end
```

And in a template:

```heex
<.link :if={allowed?(@current_scope, :update, @post)} navigate={~p"/posts/#{@post}/edit"}>
  Edit
</.link>
```

`authorize/3` returns `{:error, %Sekisho.Denied{}}`, and
`authorize!/3` raises it. Phoenix answers that with a 403.

The [Quickstart](guides/quickstart.md) goes on from here, with roles and a
LiveView.

## What you get

* **One rule for checks and lists.** `allowed?/3` and `where_allowed/3`
  come from the same condition, so a list never shows what a check
  refuses. → [Rules](guides/rules.md)
* **Roles, as many kinds as you need.** Fixed roles, roles that include
  others, and roles each org makes for itself from your permissions.
  → [Role-based access](guides/rbac.md)
* **Sharing.** Give a role on one record to a person, a team, or anyone
  with a link, for good or until a date. Access comes down nested
  folders, to any depth. → [Sharing and relations](guides/rebac.md)
* **Rules on attributes.** A plan, a status, the time, the person's own
  fields, and the fields of a record each person may see.
  → [Attribute rules](guides/abac.md)
* **All of them at once.** One app with org roles, shared projects and
  locked records, and how Sekisho decides. → [Mixing models](guides/hybrid.md)
* **Your own tables.** Roles from your memberships, relations through your
  joins, groups from your teams. → [Your own tables](guides/sources.md)
* **Why, in words.** `explain/3` gives the path that allows a permission,
  for a support page or a failing test.
  → [Testing and explanations](guides/testing.md)
* **Phoenix.** Controllers, JSON, templates, and LiveView pages that lose
  their access while open. → [Phoenix](guides/phoenix.md)
* **Fast lists.** One query, each path a set the database hashes.
  → [How it queries](guides/queries.md)

## Guides

[Quickstart](guides/quickstart.md) ·
[Rules](guides/rules.md) ·
[Role-based access](guides/rbac.md) ·
[Sharing and relations](guides/rebac.md) ·
[Attribute rules](guides/abac.md) ·
[Mixing models](guides/hybrid.md) ·
[Your own tables](guides/sources.md) ·
[Phoenix](guides/phoenix.md) ·
[Testing and explanations](guides/testing.md) ·
[How it queries](guides/queries.md)

## Development

The tests run on PostgreSQL, and make their own database:

```sh
mix deps.get
mix test          # DATABASE_URL, or postgres://postgres:postgres@localhost/sekisho_test
mix credo --strict
```

## License

MIT. See [LICENSE](https://github.com/hattoriai/sekisho/blob/main/LICENSE).
