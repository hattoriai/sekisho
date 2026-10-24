# Role-based access

In role-based access control (RBAC), people hold roles, and roles give
permissions. This guide builds the roles of a SaaS app in three steps:
fixed roles from your own table, roles that include others, and roles
each customer makes for itself.

The example is a support tool. Orgs have members; members handle
tickets.

## Fixed roles, from your memberships

Your app keeps who belongs to which org, with a role:

```elixir
schema "memberships" do
  belongs_to :org, MyApp.Orgs.Org
  belongs_to :user, MyApp.Accounts.User
  field :role, Ecto.Enum, values: [:member, :admin, :owner]
end
```

Tell Sekisho where the roles are:

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

```elixir
use Sekisho,
  repo: MyApp.Repo,
  sources: MyApp.Permissions.Sources,
  policies: [MyApp.Orgs.OrgPolicy, MyApp.Support.TicketPolicy]
```

and say what each role gives:

```elixir
defmodule MyApp.Orgs.OrgPolicy do
  use Sekisho.Policy, for: MyApp.Orgs.Org

  permissions [:read, :invite, :manage_billing, :delete]

  role :member, permissions: [:read]
  role :admin, permissions: [:invite]
  role :owner, permissions: :all

  derive :member, from: :admin
  derive :admin, from: :owner
end
```

`role` names a set of permissions. `derive :member, from: :admin` says
admins hold the member role too, so they may `:read` and `:invite`.
Owners hold all three roles, and `:all` gives them every permission.

```elixir
Permissions.allowed?(scope, :invite, org)
Org |> Permissions.where_allowed(scope, :read) |> Repo.all()   # the orgs I belong to
```

The roles stay in your table. Sekisho reads them in its query, so a new
membership counts at once, with nothing to sync.

## Permissions on what belongs to the org

A ticket belongs to an org. Its permissions come from the roles held on
the org:

```elixir
defmodule MyApp.Support.TicketPolicy do
  use Sekisho.Policy, for: MyApp.Support.Ticket
  import Ecto.Query

  alias MyApp.Accounts.User

  permissions [:read, :reply, :assign, :close, :delete]

  derive :read, from: {:org, :member}
  derive :reply, from: {:org, :member}
  derive :assign, from: {:org, :admin}
  derive :close, from: {:org, :admin}
  derive :delete, from: {:org, :owner}

  # The one it is assigned to may close it too.
  @impl true
  def allow(%User{id: id}, :close), do: dynamic([t], t.assignee_id == ^id)
end
```

`{:org, :member}` follows the ticket's `belongs_to :org`: a member of the
ticket's org may read it. The list of tickets a person may read is one
query over tickets, memberships and nothing else.

## Roles each org makes for itself

A large customer wants a "Support lead" who may assign tickets but not
invite people, and a "Billing" role that sees invoices only. Fixed roles
cannot do this. `custom_roles()` lets each org define its own, from the
permissions you declare:

```elixir
defmodule MyApp.Orgs.OrgPolicy do
  use Sekisho.Policy, for: MyApp.Orgs.Org

  permissions [
    :read,
    :"members.invite",
    :"members.manage",
    :"tickets.read",
    :"tickets.reply",
    :"tickets.assign",
    :"tickets.close",
    :"billing.view",
    :"billing.manage"
  ]

  # The same in every org, and cannot be changed.
  role :owner, permissions: :all

  custom_roles()

  grant_to [:user], by: :"members.manage"
end
```

The tickets now derive from the org's permissions, not its roles:

```elixir
derive :read, from: {:org, :"tickets.read"}
derive :reply, from: {:org, :"tickets.reply"}
derive :assign, from: {:org, :"tickets.assign"}
derive :close, from: {:org, :"tickets.close"}
```

Whoever has `:"tickets.assign"` on the org, through any role, may assign
its tickets. An org's admin makes a role and gives it to someone:

```elixir
{:ok, lead} =
  Permissions.create_role(scope, org, "Support lead", [
    :read,
    :"tickets.read",
    :"tickets.reply",
    :"tickets.assign"
  ])

{:ok, _grant} = Permissions.grant(scope, ana, "Support lead", on: org)
```

Custom roles are named by strings; the policy's own roles (`:owner`) by
atoms. Both are checked the same way:

* making, changing or deleting a role takes the permission `grant_to`
  names (`:"members.manage"` here);
* no one makes or grants a role that gives a permission they do not have
  themselves, so an admin cannot make a role more powerful than
  themselves.

The roles screen of your settings page is a form over these functions:

```elixir
{:ok, roles} = Permissions.roles(scope, org)
{:ok, role} = Permissions.update_role(scope, role, ["tickets.read", "tickets.reply"])
:ok = Permissions.delete_role(scope, role)                # and its grants
```

`update_role/3` takes permissions as atoms or as the strings of a form,
and accepts only declared ones, never making a new atom.

Changing a role changes what its holders may do at once: there is
nothing to copy into each member. When the roles change, open LiveView
pages that depend on them check their access again (see
[Phoenix](phoenix.md)).

## The first owner

A new org has no owner yet, so no one may grant the first one. Grant it
without the check when you create the org:

```elixir
Repo.transact(fn ->
  with {:ok, org} <- Repo.insert(Org.changeset(%Org{}, attrs)),
       {:ok, _} <- Permissions.grant(scope, scope.user, :owner, on: org, check: false) do
    {:ok, org}
  end
end)
```

`check: false` is for this, and for seeds. Everywhere else, let the check
run.

## Which to choose

* Roles your app defines, and that never change: `role` and `derive`,
  held in your own table (sources) or in Sekisho's grants.
* Roles your customers define: `custom_roles()`, with the permissions as
  the vocabulary they choose from.
* Both: the policy's roles (an owner who can never be locked out) and
  custom ones, in the same org.
