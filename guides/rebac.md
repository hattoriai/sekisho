# Sharing and relations

In relationship-based access control (ReBAC), access comes from how a
person relates to a record: they were given it, they belong to a team that
was, it sits in a folder they can open, it belongs to an org they run.
Google Drive works this way, and so does this guide: a drive of folders
and documents, shared with people, teams and links.

## The drive

```elixir
schema "folders" do
  field :name, :string
  belongs_to :org, MyApp.Orgs.Org
  belongs_to :parent, MyApp.Drive.Folder
end

schema "documents" do
  field :title, :string
  belongs_to :org, MyApp.Orgs.Org
  belongs_to :folder, MyApp.Drive.Folder
end
```

Folders nest to any depth. A role on a folder reaches everything inside
it.

## Levels of access

Each level includes the ones below it:

```elixir
defmodule MyApp.Drive.FolderPolicy do
  use Sekisho.Policy, for: MyApp.Drive.Folder

  permissions [:read, :comment, :update, :share, :delete]

  role :viewer, permissions: [:read]
  role :commenter, permissions: [:comment]
  role :editor, permissions: [:update]
  role :owner, permissions: [:share, :delete]

  derive :commenter, from: :editor
  derive :viewer, from: :commenter
  derive :editor, from: :owner

  # What a parent folder gives, every folder under it gives.
  derive :viewer, from: {:parent, :viewer}
  derive :commenter, from: {:parent, :commenter}
  derive :editor, from: {:parent, :editor}
  derive :owner, from: {:parent, :owner}

  grant_to [:user, :group, :link], link_up_to: :commenter
end
```

A role on the same record (`from: :editor`) makes the levels: an editor
is a commenter and a viewer. A role on a related record
(`from: {:parent, :viewer}`) follows a `belongs_to`. When the relation is
to the same schema, as a folder's parent is, Sekisho follows it all the
way up, in one recursive query.

Documents take their access from their folder:

```elixir
defmodule MyApp.Drive.DocumentPolicy do
  use Sekisho.Policy, for: MyApp.Drive.Document

  permissions [:read, :comment, :update, :share, :delete]

  role :viewer, permissions: [:read]
  role :commenter, permissions: [:comment]
  role :editor, permissions: [:update]
  role :owner, permissions: [:share, :delete]

  derive :commenter, from: :editor
  derive :viewer, from: :commenter
  derive :editor, from: :owner

  derive :viewer, from: {:folder, :viewer}
  derive :commenter, from: {:folder, :commenter}
  derive :editor, from: {:folder, :editor}
  derive :owner, from: {:folder, :owner}

  grant_to [:user, :group, :link], link_up_to: :viewer
end
```

## Sharing

```elixir
# With a person.
{:ok, _} = Permissions.grant(scope, ana, :editor, on: contracts)

# Until a date.
{:ok, _} = Permissions.grant(scope, auditor, :viewer, on: contracts, expires_at: ~U[2026-12-31 23:59:59Z])

# Taken back.
{:ok, 1} = Permissions.revoke(scope, ana, :editor, on: contracts)
```

Ana is now an editor of the Contracts folder, of every folder inside it,
and of every document in any of them. Granting the same role twice is one
grant (with the latest expiry).

Who may share, and what: `grant_to` says it takes `:share` (the default
`by:`), and Sekisho adds that no one gives a role whose permissions they
do not have. A viewer cannot make someone an editor; an editor cannot make
someone an owner.

The Share dialog lists the grants of a record:

```elixir
{:ok, grants} = Permissions.grants(scope, document)
# [%Sekisho.Grant{actor_type: "users", actor_id: 7, role: "editor", ...}, ...]
```

## Teams

A team is a group of people. Grant a role to the team, and each member
holds it:

```elixir
use Sekisho,
  repo: MyApp.Repo,
  sources: MyApp.Permissions.Sources,
  groups: [MyApp.Teams.Team],
  policies: [MyApp.Drive.FolderPolicy, MyApp.Drive.DocumentPolicy]
```

The members come from your table:

```elixir
@impl true
def members(MyApp.Teams.Team) do
  from m in MyApp.Teams.Membership, select: %{actor_id: m.user_id, group_id: m.team_id}
end
```

```elixir
{:ok, _} = Permissions.grant(scope, legal_team, :commenter, on: contracts)
```

Someone who joins the team holds the role from that moment, and someone
who leaves loses it: the membership is read in each query.

## Anyone with the link

```elixir
{:ok, %Sekisho.Grant{token: token}} = Permissions.grant(scope, :link, :viewer, on: document)
url = ~p"/d/#{document}?key=#{token}"
```

The token is shown once: the table keeps only its hash. A visitor who
opens the link shows the token in your scope, and your permissions
module returns it:

```elixir
@impl Sekisho
def link_tokens(%Scope{link_tokens: tokens}), do: tokens
def link_tokens(_scope), do: []
```

Keep the tokens a visitor followed in the session, and put them in the
scope where you build it. `link_up_to: :viewer` keeps links from giving
more than viewing; revoking `:link` takes back every link of that role on
the record.

## From the org

An org's admins see and edit everything in the org's drive, whatever was
shared with them:

```elixir
# In both policies.
derive :editor, from: {:org, :admin}
```

The org's admins come from wherever its roles are: your memberships
(sources), Sekisho's grants, or roles the org defined itself
([Role-based access](rbac.md)).

## Relations that are not a belongs_to

A document can be in several projects, through a join table. Declare the
relation in the policy, and write it in your sources:

```elixir
# DocumentPolicy
relation :projects, MyApp.Projects.Project
derive :viewer, from: {:projects, :member}
```

```elixir
# Sources
@impl true
def relation(MyApp.Drive.Document, :projects) do
  from p in MyApp.Projects.ProjectDocument,
    select: %{resource_id: p.document_id, related_id: p.project_id}
end
```

A member of any of the document's projects may read it. Any relation your
data has can be written this way, as a query.

## What it costs

Ana's list of documents is one query. Each way she could reach a document
is a set of ids: her grants, her teams' grants, the folders under those,
the orgs she runs. The database hashes each set and checks every document
against them. See [How it queries](queries.md) for the indexes to have.
