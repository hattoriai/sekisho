defmodule Sekisho.Policy do
  @moduledoc """
  The rules of one resource: an Ecto schema.

  Conditions are plain functions. `allow/2` and `deny/2` take the actor and a
  permission and return `true`, `false` or a condition on the record, an
  `Ecto.Query.dynamic/2` whose first binding is the resource:

      defmodule MyApp.Blog.PostPolicy do
        use Sekisho.Policy, for: MyApp.Blog.Post
        import Ecto.Query

        permissions [:read, :create, :update, :delete]

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

  A permission no clause matches is not allowed: there is no need for a last
  clause that returns `false`. `deny/2` wins over everything else.

  The same condition answers a check (`allowed?/3`, on the record in the
  database) and a list (`where_allowed/3`, in SQL), so they never disagree.
  A condition about the actor alone (`true`, `false`) needs no query.

  ## Roles

  Roles are the only part that is declared, because Sekisho checks them:

      permissions [:read, :comment, :update, :share, :delete]

      role :viewer, permissions: [:read]
      role :commenter, permissions: [:comment]
      role :editor, permissions: [:update]
      role :owner, permissions: [:share, :delete]

      derive :commenter, from: :editor
      derive :viewer, from: :commenter
      derive :editor, from: :owner
      derive :editor, from: {:org, :admin}
      derive :viewer, from: {:folder, :viewer}

      grant_to [:user, :group, :link], link_up_to: :viewer

    * `role` names a set of permissions.
    * `derive` gives a role from another: one of the same resource
      (`from: :editor`: editors are commenters), or one held on a related
      resource (`from: {:org, :admin}`: an org's admins are editors of its
      documents). The relation is the schema's own `belongs_to`, or one
      declared with `relation/2` and written in your `Sekisho.Sources`. A
      relation to the same schema (a folder's parent) is followed to any
      depth, with a recursive query.
    * `derive` also gives a permission from one held on a related record:
      `derive :view, from: {:org, :"investigations.view"}` (whoever has
      `:"investigations.view"` on the org, through a role or a rule, may
      `:view` its investigations), or from a role there
      (`derive :delete, from: {:org, :admin}`).
    * `grant_to` says who may be granted a role on a record (`grant/4` of
      your permissions module): people (`:user`), groups (`:group`), and
      anyone with a link (`:link`, up to a role). `by:` names the permission
      it takes to grant (`:share` by default).

  Roles held come from grants (Sekisho's table), from your own tables
  (`c:Sekisho.Sources.roles/1`), or both.

  ## Roles each record defines

  `custom_roles()` lets each record of the schema (an org) define roles of its
  own, kept in `sekisho_roles`, each a name and some of the policy's
  permissions:

      permissions [:"investigations.view", :"investigations.create", :"team.manage"]

      role :owner, permissions: :all
      custom_roles()

  The roles of the policy (`:owner`) are the same in every org and cannot
  be changed; the custom ones are made with `create_role/4` of your
  permissions module and granted by name (`grant(scope, ana, "Support", on:
  org)`). Other resources derive from the permissions they give:

      derive :view, from: {:org, :"investigations.view"}

  ## Fields

  `allow_fields/2` says which of a record's fields the actor may see:
  `:all` (the default), a list, or `{:except, fields}`. `redact/2` of your
  permissions module sets the others to `nil`.
  """

  @typedoc "What `allow/2` and `deny/2` return."
  @type condition :: boolean() | Ecto.Query.DynamicExpr.t()

  @doc "Whether the actor has the permission: everywhere, nowhere, or on the records of a condition."
  @callback allow(actor :: term(), permission :: atom()) :: condition()

  @doc "Where the actor does not have the permission, whatever else allows it."
  @callback deny(actor :: term(), permission :: atom()) :: condition()

  @doc "The fields of a record the actor may see."
  @callback allow_fields(actor :: term(), record :: struct()) ::
              :all | [atom()] | {:except, [atom()]}

  @optional_callbacks allow: 2, deny: 2, allow_fields: 2

  @doc false
  defmacro __using__(opts) do
    schema = Keyword.fetch!(opts, :for)

    quote do
      @behaviour Sekisho.Policy
      @sekisho_schema unquote(schema)

      import Sekisho.Policy,
        only: [
          permissions: 1,
          role: 2,
          derive: 2,
          relation: 2,
          grant_to: 1,
          grant_to: 2,
          custom_roles: 0
        ]

      Module.register_attribute(__MODULE__, :sekisho_permissions, accumulate: false)
      Module.register_attribute(__MODULE__, :sekisho_roles, accumulate: true)
      Module.register_attribute(__MODULE__, :sekisho_derives, accumulate: true)
      Module.register_attribute(__MODULE__, :sekisho_relations, accumulate: true)
      Module.register_attribute(__MODULE__, :sekisho_grant_to, accumulate: false)
      @sekisho_custom_roles false

      @before_compile Sekisho.Policy
    end
  end

  @doc "The permissions of the resource: every permission its rules and roles name."
  defmacro permissions(list) do
    quote do
      @sekisho_permissions unquote(list)
    end
  end

  @doc "A role and the permissions it gives (`:all` for every one)."
  defmacro role(name, opts) do
    quote do
      @sekisho_roles {unquote(name), Keyword.fetch!(unquote(opts), :permissions)}
    end
  end

  @doc """
  A role given by another: `from: :editor` (a role of the same record), or
  `from: {relation, role}` (a role held on a related record).
  """
  defmacro derive(name, opts) do
    quote do
      @sekisho_derives {unquote(name), Keyword.fetch!(unquote(opts), :from)}
    end
  end

  @doc """
  A relation that is not a `belongs_to` of the schema, to the schema given:
  its query is `c:Sekisho.Sources.relation/2`.
  """
  defmacro relation(name, schema) do
    quote do
      @sekisho_relations {unquote(name), unquote(schema)}
    end
  end

  @doc "Each record of the schema defines roles of its own (see the module's documentation)."
  defmacro custom_roles do
    quote do
      @sekisho_custom_roles true
    end
  end

  @doc "Who may be granted a role on a record: `[:user, :group, :link]`."
  defmacro grant_to(kinds, opts \\ []) do
    quote do
      @sekisho_grant_to {unquote(kinds), unquote(opts)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    permissions = Module.get_attribute(env.module, :sekisho_permissions) || []
    roles = env.module |> Module.get_attribute(:sekisho_roles) |> Enum.reverse()
    derives = env.module |> Module.get_attribute(:sekisho_derives) |> Enum.reverse()
    relations = env.module |> Module.get_attribute(:sekisho_relations) |> Enum.reverse()

    {kinds, grant_opts} = grant_options(env)
    roles = Map.new(roles, fn {name, perms} -> {name, expand(perms, permissions)} end)
    check!(env, permissions, roles, derives, kinds, grant_opts)

    data = %{
      schema: Module.get_attribute(env.module, :sekisho_schema),
      permissions: permissions,
      roles: roles,
      derives: derives,
      relations: Map.new(relations),
      grant_to: %{
        kinds: kinds,
        by: grant_opts[:by] || :share,
        link_up_to: grant_opts[:link_up_to]
      },
      custom_roles: Module.get_attribute(env.module, :sekisho_custom_roles)
    }

    quote do
      @doc false
      def __sekisho__(key), do: Map.fetch!(unquote(Macro.escape(data)), key)
    end
  end

  defp grant_options(env),
    do: Module.get_attribute(env.module, :sekisho_grant_to) || {[:user, :group], []}

  defp expand(:all, permissions), do: permissions
  defp expand(perms, _permissions) when is_list(perms), do: perms

  # What one policy can check alone: the rest (relations, the roles of other
  # resources) is checked by Sekisho.Model when the app first asks.
  defp check!(env, permissions, roles, derives, kinds, grant_opts) do
    errors =
      permission_errors(permissions) ++
        role_errors(roles, permissions) ++
        Enum.flat_map(derives, &derive_errors(&1, roles, permissions)) ++
        kind_errors(kinds) ++ link_errors(grant_opts[:link_up_to], roles)

    case errors do
      [] -> :ok
      [message | _] -> raise CompileError, file: env.file, line: env.line, description: message
    end
  end

  defp permission_errors(permissions) do
    if is_list(permissions) and Enum.all?(permissions, &is_atom/1),
      do: [],
      else: ["permissions must be a list of atoms"]
  end

  defp role_errors(roles, permissions) do
    for {role, perms} <- roles, perm <- perms, perm not in permissions do
      "role #{inspect(role)} gives #{inspect(perm)}, which is not in permissions"
    end
  end

  # Within a record, a role from a role. Across a relation, a role or a
  # permission from a role or permission of the related record (checked by
  # Sekisho.Model).
  defp derive_errors({name, from}, roles, _permissions) when is_atom(from) do
    cond do
      not Map.has_key?(roles, name) ->
        ["derive names #{inspect(name)}, which is not a role"]

      not Map.has_key?(roles, from) ->
        ["#{inspect(name)} derives from #{inspect(from)}, which is not a role"]

      true ->
        []
    end
  end

  defp derive_errors({name, {relation, other}}, roles, permissions)
       when is_atom(relation) and is_atom(other) do
    if Map.has_key?(roles, name) or name in permissions,
      do: [],
      else: ["derive names #{inspect(name)}, which is not a role or a permission"]
  end

  defp derive_errors({_name, other}, _roles, _permissions),
    do: ["derive's from: is a role or {relation, role or permission}, not #{inspect(other)}"]

  defp kind_errors(kinds) do
    for kind <- kinds, kind not in [:user, :group, :link] do
      "grant_to takes :user, :group and :link, not #{inspect(kind)}"
    end
  end

  defp link_errors(nil, _roles), do: []

  defp link_errors(up_to, roles) do
    if Map.has_key?(roles, up_to),
      do: [],
      else: ["link_up_to names #{inspect(up_to)}, which is not a role"]
  end
end
