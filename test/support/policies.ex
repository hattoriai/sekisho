defmodule SekishoTest.PostPolicy do
  @moduledoc "Rules only: a blog's posts."
  use Sekisho.Policy, for: SekishoTest.Post
  import Ecto.Query

  alias SekishoTest.User

  # :feature is an admin's only: no other clause, and no role, gives it.
  permissions [:read, :create, :update, :delete, :feature]

  @impl true
  def allow(%User{admin: true}, _permission), do: true
  def allow(%User{id: id}, :read), do: dynamic([p], p.published or p.author_id == ^id)

  def allow(%User{id: id}, permission) when permission in [:update, :delete],
    do: dynamic([p], p.author_id == ^id)

  def allow(%User{}, :create), do: true
  def allow(nil, :read), do: dynamic([p], p.published)

  @impl true
  def deny(_actor, :update), do: dynamic([p], p.locked)
end

defmodule SekishoTest.OrgPolicy do
  @moduledoc "Roles from the app's memberships (the sources), and roles each org defines."
  use Sekisho.Policy, for: SekishoTest.Org

  permissions [:read, :invite, :manage, :audit]

  role :member, permissions: [:read]
  role :admin, permissions: [:invite]
  role :owner, permissions: :all

  derive :member, from: :admin
  derive :admin, from: :owner

  grant_to [:user], by: :manage
  custom_roles()
end

defmodule SekishoTest.FolderPolicy do
  @moduledoc "Shared like Google Drive, inherited from the parent folder and the org."
  use Sekisho.Policy, for: SekishoTest.Folder

  permissions [:read, :comment, :update, :share, :delete]

  role :viewer, permissions: [:read]
  role :commenter, permissions: [:comment]
  role :editor, permissions: [:update]
  role :owner, permissions: [:share, :delete]

  derive :commenter, from: :editor
  derive :viewer, from: :commenter
  derive :editor, from: :owner

  derive :viewer, from: {:parent, :viewer}
  derive :editor, from: {:parent, :editor}
  derive :owner, from: {:parent, :owner}
  derive :editor, from: {:org, :admin}

  grant_to [:user, :group, :link], link_up_to: :commenter
end

defmodule SekishoTest.ProjectPolicy do
  @moduledoc false
  use Sekisho.Policy, for: SekishoTest.Project

  permissions [:read, :share]

  role :member, permissions: [:read]
  role :lead, permissions: [:share]

  derive :member, from: :lead
end

defmodule SekishoTest.DocumentPolicy do
  @moduledoc "Every model at once: grants, sources, relations, rules, fields."
  use Sekisho.Policy, for: SekishoTest.Document
  import Ecto.Query

  alias SekishoTest.User

  permissions [:read, :comment, :update, :share, :delete]

  role :viewer, permissions: [:read]
  role :commenter, permissions: [:comment]
  role :editor, permissions: [:update]
  role :owner, permissions: [:share, :delete]

  derive :commenter, from: :editor
  derive :viewer, from: :commenter
  derive :editor, from: :owner

  derive :viewer, from: {:folder, :viewer}
  derive :editor, from: {:folder, :editor}
  derive :owner, from: {:folder, :owner}
  derive :editor, from: {:org, :admin}
  derive :viewer, from: {:project, :member}

  # Permissions from the org: an auditor (a custom role) reads every
  # document; only the org's owners delete.
  derive :read, from: {:org, :audit}
  derive :delete, from: {:org, :owner}

  relation :project, SekishoTest.Project

  grant_to [:user, :group, :link], link_up_to: :viewer

  @impl true
  def allow(%User{id: id}, permission) when permission in [:read, :update, :delete],
    do: dynamic([d], d.author_id == ^id)

  @impl true
  def deny(_actor, :update), do: dynamic([d], d.locked)

  @impl true
  def allow_fields(%User{admin: true}, _document), do: :all
  def allow_fields(%User{id: id}, %{author_id: id}), do: :all
  def allow_fields(_actor, _document), do: {:except, [:contract_value]}
end

defmodule SekishoTest.Sources do
  @moduledoc false
  use Sekisho.Sources
  import Ecto.Query

  @impl true
  def roles(SekishoTest.Org) do
    from m in SekishoTest.Membership,
      select: %{actor_id: m.user_id, resource_id: m.org_id, role: m.role}
  end

  def roles(SekishoTest.Document) do
    from r in SekishoTest.Review,
      where: r.state == "open",
      select: %{actor_id: r.reviewer_id, resource_id: r.document_id, role: "editor"}
  end

  @impl true
  def relation(SekishoTest.Document, :project) do
    from p in SekishoTest.ProjectDocument,
      select: %{resource_id: p.document_id, related_id: p.project_id}
  end

  @impl true
  def members(SekishoTest.Team) do
    from m in SekishoTest.TeamMembership, select: %{actor_id: m.user_id, group_id: m.team_id}
  end
end

defmodule SekishoTest.Permissions do
  @moduledoc "The app's permissions module."
  use Sekisho,
    repo: SekishoTest.Repo,
    policies: [
      SekishoTest.PostPolicy,
      SekishoTest.OrgPolicy,
      SekishoTest.FolderPolicy,
      SekishoTest.ProjectPolicy,
      SekishoTest.DocumentPolicy
    ],
    sources: SekishoTest.Sources,
    groups: [SekishoTest.Team],
    pubsub: SekishoTest.PubSub

  @impl Sekisho
  def actor(%SekishoTest.Scope{user: user}), do: user
  def actor(nil), do: nil

  @impl Sekisho
  def link_tokens(%SekishoTest.Scope{links: links}), do: links
  def link_tokens(nil), do: []
end
