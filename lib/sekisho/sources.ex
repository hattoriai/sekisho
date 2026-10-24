defmodule Sekisho.Sources do
  @moduledoc """
  Roles, relations and groups from your own tables, as queries.

  Every function returns an Ecto query of a fixed shape, so Sekisho can
  join it into its own and lists stay in SQL. A schema a function has no
  clause for has none: there is no need for a last clause.

      defmodule MyApp.Permissions.Sources do
        use Sekisho.Sources
        import Ecto.Query

        # Roles on orgs, from your memberships.
        @impl true
        def roles(MyApp.Orgs.Org) do
          from m in MyApp.Orgs.Membership,
            select: %{actor_id: m.user_id, resource_id: m.org_id, role: m.role}
        end

        # An open review makes its reviewer an editor of the document.
        def roles(MyApp.Docs.Document) do
          from r in MyApp.Docs.Review,
            where: r.state == :open,
            select: %{actor_id: r.reviewer_id, resource_id: r.document_id, role: "editor"}
        end

        # A relation that is not a belongs_to (declared in the policy with
        # relation :workspace, MyApp.Workspace).
        @impl true
        def relation(MyApp.Docs.Document, :workspace) do
          from d in MyApp.Docs.Document,
            join: f in assoc(d, :folder),
            select: %{resource_id: d.id, related_id: f.workspace_id}
        end

        # Who is in a group (a schema in `groups:` of your permissions module).
        @impl true
        def members(MyApp.Teams.Team) do
          from m in MyApp.Teams.Membership, select: %{actor_id: m.user_id, group_id: m.team_id}
        end
      end
  """

  @doc "Who holds which role on which record of the schema: `actor_id`, `resource_id`, `role`."
  @callback roles(schema :: module()) :: Ecto.Queryable.t()

  @doc "A relation of the schema: `resource_id` and `related_id`."
  @callback relation(schema :: module(), name :: atom()) :: Ecto.Queryable.t()

  @doc "The members of the groups of a schema: `actor_id` and `group_id`."
  @callback members(group :: module()) :: Ecto.Queryable.t()

  @optional_callbacks roles: 1, relation: 2, members: 1

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Sekisho.Sources
    end
  end
end
