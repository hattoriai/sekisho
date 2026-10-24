# Rules

A rule says who may do what, in a function. It is the first thing to
reach for, and many apps need nothing else.

## allow and deny

`allow/2` takes the actor (a user, or `nil` for a visitor) and a
permission. It returns one of three things:

* `true`: allowed on every record;
* `false`: allowed on none;
* a condition on the record, an `Ecto.Query.dynamic/2` whose first
  binding is the resource.

```elixir
defmodule MyApp.Tasks.TaskPolicy do
  use Sekisho.Policy, for: MyApp.Tasks.Task
  import Ecto.Query

  alias MyApp.Accounts.User

  permissions [:read, :create, :update, :complete, :delete]

  @impl true
  def allow(%User{role: :manager}, _permission), do: true
  def allow(%User{}, :create), do: true
  def allow(%User{id: id}, :read), do: dynamic([t], t.assignee_id == ^id or t.creator_id == ^id)
  def allow(%User{id: id}, :complete), do: dynamic([t], t.assignee_id == ^id)
  def allow(%User{id: id}, permission) when permission in [:update, :delete],
    do: dynamic([t], t.creator_id == ^id)

  @impl true
  def deny(_user, permission) when permission in [:update, :complete],
    do: dynamic([t], t.archived)
end
```

`deny/2` takes the same arguments and returns the same kinds of answer.
It wins over everything: here a manager may do anything, except change
an archived task.

A permission no clause matches is not allowed. There is no last clause
returning `false` to write, though you may write one if you like it
explicit.

`permissions` lists every permission of the resource. Asking for one that
is not there raises, so a typo (`:udpate`) is an error, not a quiet "no".

## Conditions are checked in the database

`allowed?(scope, :complete, task)` runs the condition against the task's
row, with one query on its primary key. It reads the task as it is in the
database, not the struct in your hands: a change you have not saved does
not count.

A rule about the actor alone (`true`, `false`) needs no query at all.
`allowed?(scope, :create, Task)` takes the schema, since there is no
record yet. Asking about the schema when the answer depends on the record
raises, and says so.

## Lists

`where_allowed/3` takes a query and keeps the records on which the
permission holds:

```elixir
Task
|> where([t], t.project_id == ^project.id)
|> Permissions.where_allowed(scope, :read)
|> order_by(:due_on)
|> Repo.all()
```

The condition is the same one `allowed?/3` uses. When the answer is
`true`, the query is left as it is; when it is `false`, it returns
nothing, without asking the database.

## Many records at once

A table of tasks with a Complete and a Delete button on each row would
ask twice per row. `with_permissions/3` asks once:

```elixir
Permissions.with_permissions(tasks, scope, [:complete, :delete])
#=> [{%Task{id: 1}, [:complete]}, {%Task{id: 2}, [:complete, :delete]}, ...]
```

The records keep their order.

## What rules see

The actor is whatever `actor/1` of your permissions module returns: your
user struct, with whatever it has loaded. Rules match on it as any
Elixir function does:

```elixir
def allow(%User{plan: :pro}, :export), do: true
def allow(%User{suspended_at: %DateTime{}}, _permission), do: false
```

For things that are not the user's (the request's IP, the org being
browsed), put them in the scope and return them in the actor. The
[Attribute rules](abac.md) guide shows how.

## When a rule is not enough

Rules are the right tool when "who" is a fact about the actor and the
record: an author, an assignee, a manager. When "who" is a list of people
someone chose (members of an org, people a folder was shared with), use
roles: [Role-based access](rbac.md), [Sharing and relations](rebac.md).
Rules and roles work together in one policy: either allows, and `deny/2`
refuses both.
