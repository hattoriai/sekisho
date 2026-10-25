defmodule Sekisho do
  @moduledoc """
  Permissions for Phoenix.

  Your app has one permissions module, which lists its policies:

      defmodule MyApp.Permissions do
        use Sekisho,
          repo: MyApp.Repo,
          policies: [MyApp.Blog.PostPolicy, MyApp.Docs.DocumentPolicy, MyApp.Orgs.OrgPolicy],
          sources: MyApp.Permissions.Sources,
          groups: [MyApp.Teams.Team]

        @impl Sekisho
        def actor(%MyApp.Accounts.Scope{user: user}), do: user
        def actor(nil), do: nil
      end

  and every question goes through it, with your scope (Phoenix's
  `%Scope{}`) first:

      MyApp.Permissions.allowed?(scope, :update, post)        # true | false
      MyApp.Permissions.authorize(scope, :update, post)       # :ok | {:error, %Sekisho.Denied{}}
      MyApp.Permissions.authorize!(scope, :update, post)      # raises Sekisho.Denied, a 403

      Post |> MyApp.Permissions.where_allowed(scope, :read) |> Repo.all()
      MyApp.Permissions.with_permissions(posts, scope, [:update, :delete])

      MyApp.Permissions.allowed_fields(scope, user)
      MyApp.Permissions.redact(scope, user)
      MyApp.Permissions.explain(scope, :update, document)

      MyApp.Permissions.grant(scope, ana, :editor, on: document)
      MyApp.Permissions.grant(scope, :link, :viewer, on: document)
      MyApp.Permissions.revoke(scope, ana, :editor, on: document)
      MyApp.Permissions.grants(scope, document)

      {:ok, support} = MyApp.Permissions.create_role(scope, org, "Support", [:"investigations.view"])
      MyApp.Permissions.grant(scope, ana, "Support", on: org)

  The rules are in policies (`Sekisho.Policy`), and roles held in your own
  tables in sources (`Sekisho.Sources`).

  ## Options

    * `:repo`: your Ecto repo. Required, unless the module has a `repo/0`
      (see "A repo known at runtime").
    * `:policies`: your policies (required). They are read when the module
      is first asked, not when it compiles, so a change to one recompiles no
      other; `validate!/0` checks them together (in a test, or at boot).
    * `:sources`: your `Sekisho.Sources` module.
    * `:groups`: the schemas of groups that may be granted roles (teams);
      their members come from `c:Sekisho.Sources.members/1`.
    * `:pubsub`: your `Phoenix.PubSub`, on which grants and revocations are
      broadcast (topic `"sekisho"`).
    * `:deny_as`: `:forbidden` (403, the default) or `:not_found` (404).
    * `:tables`: the start of the names of Sekisho's tables, `"sekisho"` by
      default (`sekisho_grants`, `sekisho_roles`, `sekisho_role_permissions`).
      A library that keeps its own grants apart from its host's names its
      own, and migrates them with `use Sekisho.Migrations, tables: ...`.

  ## A repo known at runtime

  A library built into another app does not know its host's repo when it
  compiles. Leave `repo:` out and give the module a `repo/0`, asked once for
  each question:

      defmodule MyLib.Permissions do
        use Sekisho, policies: [MyLib.ReportPolicy]

        @impl Sekisho
        def repo, do: Application.fetch_env!(:my_lib, :repo)

        @impl Sekisho
        def actor(scope), do: scope.user
      end

  A module with neither `repo:` nor `repo/0`, or with both, does not compile.

  ## Checks of a record

  A check of a record asks the database: the record as it is there, with
  one query on its primary key. A rule about the actor alone (`true`,
  `false`) needs none. To ask about many records at once, use
  `with_permissions/3`.
  """

  import Ecto.Query

  alias Sekisho.{Call, Condition, Context, Denied, Explanation, Model}

  @doc """
  Your Ecto repo: the `repo:` of `use Sekisho`, or your own function, for a
  repo known only at runtime.
  """
  @callback repo() :: module()

  @doc "The actor your scope is: a user struct, or `nil` for a visitor."
  @callback actor(scope :: term()) :: struct() | nil

  @doc """
  The link tokens your scope holds (from a link a visitor followed): `[]` by
  default.
  """
  @callback link_tokens(scope :: term()) :: [String.t()]

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Sekisho
      @sekisho_config Sekisho.Config.new!(opts)
      @before_compile Sekisho

      @doc false
      def __sekisho__(:config), do: @sekisho_config

      @impl Sekisho
      def link_tokens(_scope), do: []
      defoverridable link_tokens: 1

      @doc "Whether the scope has the permission on the resource (a record, or a schema)."
      def allowed?(scope, permission, resource),
        do: Sekisho.allowed?(__MODULE__, scope, permission, resource)

      @doc "`:ok`, or `{:error, %Sekisho.Denied{}}`."
      def authorize(scope, permission, resource),
        do: Sekisho.authorize(__MODULE__, scope, permission, resource)

      @doc "`:ok`, or raises `Sekisho.Denied` (a 403)."
      def authorize!(scope, permission, resource),
        do: Sekisho.authorize!(__MODULE__, scope, permission, resource)

      @doc "The query, limited to the records on which the scope has the permission."
      def where_allowed(queryable, scope, permission),
        do: Sekisho.where_allowed(__MODULE__, queryable, scope, permission)

      @doc "Each record, with those of the permissions the scope has on it: one query."
      def with_permissions(records, scope, permissions),
        do: Sekisho.with_permissions(__MODULE__, records, scope, permissions)

      @doc "The fields of the record the scope may see."
      def allowed_fields(scope, record), do: Sekisho.allowed_fields(__MODULE__, scope, record)

      @doc "The record, with the fields the scope may not see set to nil."
      def redact(scope, record), do: Sekisho.redact(__MODULE__, scope, record)

      @doc "Why the scope has the permission on the record, or why not."
      def explain(scope, permission, record),
        do: Sekisho.explain(__MODULE__, scope, permission, record)

      @doc "Grants a role on a record (`on:`) to a user, a group or `:link`."
      def grant(scope, to, role, opts),
        do: Sekisho.Grants.grant(__MODULE__, scope, to, role, opts)

      @doc "Revokes a role on a record (`on:`) from a user, a group or `:link`."
      def revoke(scope, to, role, opts),
        do: Sekisho.Grants.revoke(__MODULE__, scope, to, role, opts)

      @doc "The grants on a record."
      def grants(scope, record), do: Sekisho.Grants.list(__MODULE__, scope, record)

      @doc "Makes a role the record defines for itself (`custom_roles`), with some of its permissions."
      def create_role(scope, record, name, permissions, opts \\ []),
        do: Sekisho.Roles.create(__MODULE__, scope, record, name, permissions, opts)

      @doc "Changes the permissions a custom role gives."
      def update_role(scope, role, permissions, opts \\ []),
        do: Sekisho.Roles.update(__MODULE__, scope, role, permissions, opts)

      @doc "Deletes a custom role, and its grants."
      def delete_role(scope, role, opts \\ []),
        do: Sekisho.Roles.delete(__MODULE__, scope, role, opts)

      @doc "The custom roles of a record."
      def roles(scope, record), do: Sekisho.Roles.list(__MODULE__, scope, record)

      @doc """
      Tells open pages (`Sekisho.LiveView`) that permissions changed in your
      own tables (a membership): they check their access again.
      """
      def changed, do: Sekisho.changed(__MODULE__)

      @doc "Checks the policies together: their relations, and the roles they derive from."
      def validate!, do: Sekisho.validate!(__MODULE__)
    end
  end

  @doc false
  # The repo: `repo:`, made a repo/0, or the module's own repo/0. Never both,
  # and never neither, so a module without a repo does not compile.
  defmacro __before_compile__(env) do
    config = Module.get_attribute(env.module, :sekisho_config)
    defined? = Module.defines?(env.module, {:repo, 0}, :def)

    case {config.repo, defined?} do
      {nil, true} ->
        :ok

      {nil, false} ->
        raise ArgumentError, "use Sekisho needs repo:, or a repo/0 in #{inspect(env.module)}"

      {_repo, true} ->
        raise ArgumentError,
              "#{inspect(env.module)} has repo: and a repo/0: give one of them"

      {repo, false} ->
        quote do
          @impl Sekisho
          def repo, do: unquote(repo)
        end
    end
  end

  ## Checks

  @doc false
  def allowed?(root, scope, permission, resource) do
    ctx = Context.new(root, scope)
    decide(ctx, permission, resource)
  end

  @doc false
  def decide(ctx, permission, resource) do
    {schema, record} = target!(resource)
    condition = Condition.build(ctx, schema, permission)

    allowed =
      case {condition, record} do
        {result, _record} when is_boolean(result) ->
          result

        {_condition, nil} ->
          raise ArgumentError,
                "whether #{inspect(permission)} is allowed on #{inspect(schema)} depends on the " <>
                  "record: pass one"

        {condition, record} ->
          key = Model.primary_key(schema)
          id = Map.fetch!(record, key)
          query = from x in schema, where: field(x, ^key) == ^id, where: ^condition
          ctx.repo.exists?(query)
      end

    :telemetry.execute([:sekisho, :decision], %{}, %{
      root: ctx.root,
      permission: permission,
      schema: schema,
      allowed: allowed
    })

    allowed
  end

  @doc false
  def authorize(root, scope, permission, resource) do
    ctx = Context.new(root, scope)

    if decide(ctx, permission, resource) do
      :ok
    else
      status = if ctx.model.config.deny_as == :not_found, do: 404, else: 403
      {:error, %Denied{permission: permission, resource: resource, plug_status: status}}
    end
  end

  @doc false
  def authorize!(root, scope, permission, resource) do
    case authorize(root, scope, permission, resource) do
      :ok -> :ok
      {:error, denied} -> raise denied
    end
  end

  ## Lists

  @doc false
  def where_allowed(root, queryable, scope, permission) do
    ctx = Context.new(root, scope)
    query = Ecto.Queryable.to_query(queryable)
    schema = schema_of!(query)

    case Condition.build(ctx, schema, permission) do
      true -> query
      false -> where(query, false)
      condition -> where(query, ^condition)
    end
  end

  @doc false
  def with_permissions(_root, [], _scope, _permissions), do: []

  def with_permissions(root, [%{__struct__: schema} | _] = records, scope, permissions) do
    ctx = Context.new(root, scope)
    key = Model.primary_key(schema)
    conditions = Map.new(permissions, &{&1, Condition.build(ctx, schema, &1)})
    asked = for {permission, condition} <- conditions, not is_boolean(condition), do: permission

    answers =
      case asked do
        [] ->
          %{}

        asked ->
          ids = Enum.map(records, &Map.fetch!(&1, key))

          selected =
            Map.new(asked, fn permission ->
              {permission, Map.fetch!(conditions, permission)}
            end)

          from(x in schema, where: field(x, ^key) in ^ids)
          |> select([x], %{id: field(x, ^key)})
          |> select_merge(^selected)
          |> ctx.repo.all()
          |> Map.new(&{&1.id, &1})
      end

    Enum.map(records, fn record ->
      row = Map.get(answers, Map.fetch!(record, key), %{})
      {record, Enum.filter(permissions, &held?(Map.fetch!(conditions, &1), row, &1))}
    end)
  end

  defp held?(result, _row, _permission) when is_boolean(result), do: result
  # A condition selected as a value: true, or 1 where the database has no
  # booleans (SQLite, MySQL).
  defp held?(_condition, row, permission), do: Map.get(row, permission) in [true, 1]

  ## Fields

  @doc false
  def allowed_fields(root, scope, %{__struct__: schema} = record) do
    ctx = Context.new(root, scope)
    policy = Model.policy!(ctx.model, schema)
    fields = schema.__schema__(:fields)

    case Call.optional(policy, :allow_fields, [ctx.actor, record]) || :all do
      :all -> fields
      {:except, hidden} -> fields -- hidden
      shown when is_list(shown) -> Enum.filter(fields, &(&1 in shown))
    end
  end

  @doc false
  def redact(root, scope, %{__struct__: schema} = record) do
    shown = allowed_fields(root, scope, record)
    keep = [Model.primary_key(schema) | shown]
    hidden = schema.__schema__(:fields) -- keep
    Enum.reduce(hidden, record, &Map.put(&2, &1, nil))
  end

  ## Explanations

  @doc false
  def explain(root, scope, permission, %{__struct__: schema} = record) do
    ctx = Context.new(root, scope)
    _ = Condition.build(ctx, schema, permission)
    {reasons, denied} = Sekisho.Explain.why(ctx, record, permission, [])

    %Explanation{
      permission: permission,
      resource: record,
      allowed?: reasons != [] and not denied,
      denied: denied,
      reasons: reasons
    }
  end

  @doc false
  def matches?(ctx, %{__struct__: schema} = record, condition) do
    key = Model.primary_key(schema)
    id = Map.fetch!(record, key)

    ctx.repo.exists?(from x in schema, where: field(x, ^key) == ^id, where: ^condition)
  end

  @doc false
  def changed(root) do
    if pubsub = root.__sekisho__(:config).pubsub do
      Phoenix.PubSub.broadcast(pubsub, "sekisho", {:sekisho, :changed, %{}})
    end

    :ok
  end

  ## The whole

  @doc false
  def validate!(root) do
    Model.reset(root)
    Model.get(root)
    :ok
  end

  defp target!(%{__struct__: schema} = record) do
    key = Model.primary_key(schema)
    if Map.get(record, key), do: {schema, record}, else: {schema, nil}
  end

  defp target!(schema) when is_atom(schema), do: {schema, nil}

  defp schema_of!(%Ecto.Query{from: %{source: {_source, schema}}})
       when is_atom(schema) and not is_nil(schema),
       do: schema

  defp schema_of!(query),
    do: raise(ArgumentError, "where_allowed/3 needs a query from a schema, not #{inspect(query)}")
end
