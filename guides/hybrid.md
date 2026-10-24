# Mixing models

Real apps are not one model. This guide builds the permissions of a
project tool where four kinds of rule meet, and then shows how Sekisho
decides when they disagree.

The app: orgs, with roles each org defines; projects in an org, shared
with people and teams; tasks in projects; and some facts that override
everything (an archived project, a free plan).

## The schemas

```elixir
schema "orgs" do
  field :name, :string
  field :plan, Ecto.Enum, values: [:free, :team, :business]
end

schema "projects" do
  field :name, :string
  field :archived, :boolean, default: false
  field :visibility, Ecto.Enum, values: [:private, :org]
  belongs_to :org, Org
end

schema "tasks" do
  field :title, :string
  field :budget, :integer
  belongs_to :project, Project
  belongs_to :assignee, User
end
```

## The org: roles it defines

```elixir
defmodule MyApp.Orgs.OrgPolicy do
  use Sekisho.Policy, for: MyApp.Orgs.Org

  permissions [
    :read,
    :"members.manage",
    :"projects.create",
    :"projects.read_all",
    :"projects.manage_all",
    :"budgets.read"
  ]

  role :owner, permissions: :all
  role :member, permissions: [:read]
  derive :member, from: :owner

  custom_roles()

  grant_to [:user], by: :"members.manage"
end
```

The owner and member roles are the same in every org. The rest (a
"Project manager" with `:"projects.manage_all"`, a "Finance" role with
`:"budgets.read"`) each org makes for itself.

## The project: shared, and from the org

```elixir
defmodule MyApp.Projects.ProjectPolicy do
  use Sekisho.Policy, for: MyApp.Projects.Project
  import Ecto.Query

  alias MyApp.Accounts.User
  alias MyApp.Orgs.Membership

  permissions [:read, :update, :share, :archive]

  role :viewer, permissions: [:read]
  role :editor, permissions: [:update]
  role :admin, permissions: [:share, :archive]

  derive :viewer, from: :editor
  derive :editor, from: :admin

  # From the org: its custom roles, through their permissions.
  derive :viewer, from: {:org, :"projects.read_all"}
  derive :admin, from: {:org, :"projects.manage_all"}

  grant_to [:user, :group]

  # Projects open to the whole org: every member reads them.
  @impl true
  def allow(%User{id: id}, :read) do
    dynamic(
      [p],
      p.visibility == :org and
        p.org_id in subquery(from m in Membership, where: m.user_id == ^id, select: m.org_id)
    )
  end

  # Archived projects are read-only, whoever you are.
  @impl true
  def deny(_user, permission) when permission in [:update, :share],
    do: dynamic([p], p.archived)
end
```

Four sources of access, in one policy:

1. **Grants** (ReBAC): Ana was made an editor of this project.
2. **Roles derived from the org** (RBAC): Bruno holds the org's
   "Project manager", which gives `:"projects.manage_all"`, so he is an
   admin of every project in it.
3. **A rule** (ABAC): the project is open to the org, and Carla is a
   member.
4. **A deny** (ABAC): the project is archived, so no one updates it.

## The task: from its project, and its own facts

```elixir
defmodule MyApp.Projects.TaskPolicy do
  use Sekisho.Policy, for: MyApp.Projects.Task
  import Ecto.Query

  alias MyApp.Accounts.User
  alias MyApp.Projects.Project

  permissions [:read, :update, :complete]

  derive :read, from: {:project, :read}
  derive :update, from: {:project, :update}

  @impl true
  def allow(%User{id: id}, :complete), do: dynamic([t], t.assignee_id == ^id)

  @impl true
  def deny(_user, :complete),
    do: dynamic([t], t.project_id in subquery(from p in Project, where: p.archived, select: p.id))

  # The budget, only for those whose org role reads budgets.
  @impl true
  def allow_fields(_user, _task), do: {:except, [:budget]}
end
```

`derive :read, from: {:project, :read}` takes the project's whole
answer: grants, org roles, the rule for open projects, and the deny for
archived ones. A task is readable exactly when its project is.

For the budget, the field rule needs to know a role, so ask in the
context and pass the answer:

```elixir
def task_for_display(scope, task) do
  org = Repo.preload(task, project: :org).project.org

  if Permissions.allowed?(scope, :"budgets.read", org),
    do: task,
    else: Permissions.redact(scope, task)
end
```

## The plan

A free org may not create more than three projects. That is a fact about
the org and its data, so it is a rule, on the org:

```elixir
# OrgPolicy
@impl true
def deny(_user, :"projects.create") do
  dynamic(
    [o],
    o.plan == :free and
      fragment("(SELECT count(*) FROM projects WHERE org_id = ?)", o.id) >= 3
  )
end
```

It wins over the owner's `:all`. What a plan includes in general (which
features a customer bought) is better kept in its own place than in
permissions: entitlements, asked in the same context, before Sekisho.

## How Sekisho decides

For a permission on a record, Sekisho asks every path at once:

    allowed = (a rule allows OR a role that gives it is held) AND NOT a deny refuses

* **Allow paths are OR'd.** A grant, a role from your tables, a role from
  a related record, a custom role, a rule: any one is enough.
* **Deny wins.** A `deny/2` that matches refuses, whatever allowed it,
  including `true` for an admin.
* **Derived answers keep their deny.** A permission derived from a
  related record (`from: {:project, :update}`) is that record's whole
  answer, deny included.
* **Nothing is cached between requests.** A grant, a membership or a
  role change counts at the next question.

And it tells you which path it took:

```elixir
iex> Permissions.explain(scope, :update, task)
#Sekisho.Explanation<allowed :update on MyApp.Projects.Task 41
  has :update through :project: MyApp.Projects.Project 7
    holds :admin through :org: MyApp.Orgs.Org 2
      holds "Project manager": granted to users 12>
```

## A checklist for your own

* Start with rules. Add a role when a person, not a fact, decides who.
* One permission per thing a person can do, named as your UI names it.
* Declare relations once, where the data has them: `derive` follows your
  `belongs_to`; anything else is a query in your sources.
* Put everything that must never happen in `deny/2`.
* Test the paths, not the implementation: `assert_allowed` for each kind
  of person, and `validate!/0` once ([Testing](testing.md)).
