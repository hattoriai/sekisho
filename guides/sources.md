# Your own tables

Your app already knows a lot about who may do what: memberships, teams,
the reviewer of a document, the members of a project. Sekisho reads it
where it is, through a sources module, instead of asking you to copy it
into grants.

```elixir
defmodule MyApp.Permissions.Sources do
  use Sekisho.Sources
  import Ecto.Query
end
```

```elixir
use Sekisho,
  repo: MyApp.Repo,
  sources: MyApp.Permissions.Sources,
  policies: [...]
```

Each function returns an Ecto query of a fixed shape. Sekisho joins it
into its own, so a list is still one query, and a change in your table
counts at the next question. A schema a function has no clause for has
none: there is no last clause to write.

## roles/1: who holds which role

```elixir
@impl true
def roles(MyApp.Orgs.Org) do
  from m in MyApp.Orgs.Membership,
    select: %{actor_id: m.user_id, resource_id: m.org_id, role: m.role}
end
```

The three fields are the actor's id, the record's id and the role's name,
as a string, an atom or an `Ecto.Enum`. A role can come from anything you
can query:

```elixir
# An open review makes its reviewer an editor.
def roles(MyApp.Docs.Document) do
  from r in MyApp.Docs.Review,
    where: r.state == :open,
    select: %{actor_id: r.reviewer_id, resource_id: r.document_id, role: "editor"}
end

# The creator of a project is its admin.
def roles(MyApp.Projects.Project) do
  from p in MyApp.Projects.Project,
    select: %{actor_id: p.creator_id, resource_id: p.id, role: "admin"}
end
```

Roles from sources and roles from grants add up: a record may have both.

## relation/2: relations that are not a belongs_to

`derive` follows a `belongs_to` of the schema by itself. Anything else (a
join table, a relation through another record) is declared in the policy
and written here:

```elixir
# The policy
relation :projects, MyApp.Projects.Project
derive :viewer, from: {:projects, :member}
```

```elixir
@impl true
def relation(MyApp.Docs.Document, :projects) do
  from p in MyApp.Projects.ProjectDocument,
    select: %{resource_id: p.document_id, related_id: p.project_id}
end

# A document's workspace, through its folder.
def relation(MyApp.Docs.Document, :workspace) do
  from d in MyApp.Docs.Document,
    join: f in assoc(d, :folder),
    select: %{resource_id: d.id, related_id: f.workspace_id}
end
```

`resource_id` is the record's id, `related_id` the related record's.

## members/1: who is in a group

A group (a team, a department) can be granted roles. Name its schema in
`groups:` and say who is in it:

```elixir
use Sekisho, groups: [MyApp.Teams.Team], ...
```

```elixir
@impl true
def members(MyApp.Teams.Team) do
  from m in MyApp.Teams.Membership, select: %{actor_id: m.user_id, group_id: m.team_id}
end
```

## Open pages

LiveView pages that watch a record check their access again when a grant
or a role changes. Sekisho does not see your tables change, so tell it
after you change a membership:

```elixir
def remove_member(scope, membership) do
  with {:ok, membership} <- Repo.delete(membership) do
    Permissions.changed()
    {:ok, membership}
  end
end
```

## Indexes

The queries filter your tables by the actor's id. Index the columns your
sources read by: `memberships(user_id)`, `team_memberships(user_id)`,
`reviews(reviewer_id)`. See [How it queries](queries.md).
