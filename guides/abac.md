# Attribute rules

In attribute-based access control (ABAC), the answer comes from facts:
the person's plan, the record's status, the time, where the request came
from. In Sekisho these are rules, plain functions, with three places to
find the facts:

* the actor (your user struct, and what you put next to it);
* the record (through a condition, in the database);
* the scope (what your app knows about the request).

The example is an expense tool.

## Facts about the record

```elixir
defmodule MyApp.Expenses.ExpensePolicy do
  use Sekisho.Policy, for: MyApp.Expenses.Expense
  import Ecto.Query

  alias MyApp.Accounts.User
  alias MyApp.Expenses.Expense

  permissions [:read, :update, :submit, :approve, :pay]

  @impl true
  def allow(%User{id: id}, permission) when permission in [:read, :update, :submit],
    do: dynamic([e], e.employee_id == ^id)

  # Managers approve their reports' expenses, up to their limit.
  def allow(%User{id: id, approval_limit: limit}, :approve),
    do: dynamic([e], e.manager_id == ^id and e.amount <= ^limit)

  def allow(%User{department: :finance}, permission) when permission in [:read, :pay], do: true

  @impl true
  # Nothing changes once it is submitted; only approved expenses are paid.
  def deny(_user, :update), do: dynamic([e], e.status != :draft)
  def deny(_user, :approve), do: dynamic([e], e.status != :submitted)
  def deny(_user, :pay), do: dynamic([e], e.status != :approved)
end
```

Each condition is SQL, so "the expenses I may approve" is one query:

```elixir
Expense |> Permissions.where_allowed(scope, :approve) |> Repo.all()
```

## Facts about the person

Whatever your user struct has, a rule can match on:

```elixir
def allow(%User{suspended_at: %DateTime{}}, _permission), do: false
def allow(%User{plan: plan}, :export) when plan in [:team, :business], do: true
```

Clauses are tried in order, as in any Elixir function: put the ones that
refuse first, or use `deny/2`, which wins over everything.

## Facts about the request

The time, the IP, the org being browsed, whether the session was made
with a second factor: these belong to the request, not to the user. Put
them in your scope, and have `actor/1` return them with the user:

```elixir
defmodule MyApp.Permissions do
  use Sekisho, repo: MyApp.Repo, policies: [...]

  defmodule Actor do
    defstruct [:user, :ip, :mfa?, :now]
  end

  @impl Sekisho
  def actor(%Scope{user: nil}), do: nil
  def actor(%Scope{} = scope), do: %Actor{user: scope.user, ip: scope.ip, mfa?: scope.mfa?, now: DateTime.utc_now()}
end
```

```elixir
# Paying takes a second factor, from the office network.
def deny(%Actor{mfa?: false}, :pay), do: true
def deny(%Actor{ip: ip}, :pay), do: not MyApp.Network.office?(ip)
```

The actor is not a schema here, so it cannot be granted roles. When you
need both, keep the user as the actor and read the request's facts from
the scope in your context, before you ask; or give the user struct a
virtual field your scope fills.

## Fields

Some people may see a record but not all of it: the salary on an
employee's page, the bank details on an expense. `allow_fields/2` says
which fields the actor sees:

```elixir
@impl true
def allow_fields(%User{department: :finance}, _expense), do: :all
def allow_fields(%User{id: id}, %Expense{employee_id: id}), do: :all
def allow_fields(_user, _expense), do: {:except, [:iban, :receipt_url]}
```

```elixir
Permissions.allowed_fields(scope, expense)   # [:id, :amount, :status, ...]
Permissions.redact(scope, expense)           # the struct, with iban and receipt_url as nil
```

Use `redact/2` in a JSON view or before you assign to a LiveView, so a
field that is not shown is not sent either.

## Rules or roles

Attributes are the right tool when a fact decides: a status, a limit, a
department. When a person decides (who was invited, who a folder was
shared with), use roles and grants. Most apps mix both:
[Mixing models](hybrid.md).
