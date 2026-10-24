defmodule Sekisho.Grants do
  @moduledoc false
  # grant/4, revoke/4 and grants/2 of a permissions module.
  #
  # Granting and revoking are themselves checked: they take the permission
  # the policy's grant_to names (`by:`, :share by default) and every
  # permission of the role, so no one gives or takes a role above their own.
  # `check: false` skips the check, for seeds and for the first owner of a
  # record just created.
  #
  # A role is a role of the policy (an atom), or one the record defines
  # (custom_roles, by its name: a string).

  import Ecto.Query

  alias Sekisho.{Context, Denied, Grant, Model, Role}

  def grant(root, scope, to, role, opts) do
    {resource, opts} = Keyword.pop!(opts, :on)
    ctx = Context.new(root, scope)
    {schema, id} = record!(resource)
    policy = Model.policy!(ctx.model, schema)
    permissions = role_permissions!(ctx, policy, resource, role)
    {kind, actor_type, actor_id} = grantee!(ctx, policy, to)
    link_role!(ctx, policy, kind, role)

    with :ok <- check(ctx, opts, resource, permissions) do
      grant = %Grant{
        resource_type: Model.type(ctx.model, schema),
        resource_id: id,
        actor_type: actor_type,
        actor_id: actor_id,
        role: to_string(role),
        granted_by_id: ctx.actor_id,
        expires_at: opts[:expires_at]
      }

      result = insert(ctx, kind, grant)
      with {:ok, grant} <- result, do: broadcast(ctx, grant, :granted)
      result
    end
  end

  def revoke(root, scope, to, role, opts) do
    {resource, opts} = Keyword.pop!(opts, :on)
    ctx = Context.new(root, scope)
    {schema, id} = record!(resource)
    policy = Model.policy!(ctx.model, schema)
    permissions = role_permissions!(ctx, policy, resource, role)
    {_kind, actor_type, actor_id} = grantee!(ctx, policy, to)

    with :ok <- check(ctx, opts, resource, permissions) do
      type = Model.type(ctx.model, schema)
      name = to_string(role)

      query =
        from g in Grant,
          where: g.resource_type == ^type and g.resource_id == ^id,
          where: g.actor_type == ^actor_type and g.role == ^name

      query = if actor_id, do: where(query, [g], g.actor_id == ^actor_id), else: query
      {count, _} = ctx.model.config.repo.delete_all(query)

      if count > 0 do
        broadcast(
          ctx,
          %Grant{
            resource_type: type,
            resource_id: id,
            actor_type: actor_type,
            actor_id: actor_id,
            role: name
          },
          :revoked
        )
      end

      {:ok, count}
    end
  end

  def list(root, scope, resource) do
    ctx = Context.new(root, scope)
    {schema, id} = record!(resource)
    policy = Model.policy!(ctx.model, schema)

    with :ok <- authorize(ctx, policy.__sekisho__(:grant_to).by, resource) do
      type = Model.type(ctx.model, schema)

      grants =
        ctx.model.config.repo.all(
          from g in Grant,
            where: g.resource_type == ^type and g.resource_id == ^id,
            order_by: [asc: g.inserted_at, asc: g.id]
        )

      {:ok, grants}
    end
  end

  ## Checks

  # The permission that grants on the record, and every permission given:
  # one query.
  @doc false
  def check(ctx, opts, resource, permissions) do
    if Keyword.get(opts, :check, true) do
      %{__struct__: schema} = resource
      policy = Model.policy!(ctx.model, schema)
      needed = Enum.uniq([policy.__sekisho__(:grant_to).by | permissions])

      case Sekisho.with_permissions(ctx.root, [resource], ctx.scope, needed) do
        [{_record, held}] when length(held) == length(needed) -> :ok
        [{_record, held}] -> denied(ctx, hd(needed -- held), resource)
      end
    else
      :ok
    end
  end

  @doc false
  def authorize(ctx, permission, resource) do
    if Sekisho.decide(ctx, permission, resource), do: :ok, else: denied(ctx, permission, resource)
  end

  defp denied(ctx, permission, resource) do
    status = if ctx.model.config.deny_as == :not_found, do: 404, else: 403
    {:error, %Denied{permission: permission, resource: resource, plug_status: status}}
  end

  @doc false
  def record!(%{__struct__: schema} = record) do
    case Map.fetch!(record, Model.primary_key(schema)) do
      nil ->
        raise ArgumentError, "a grant is on a record that is saved, not a new #{inspect(schema)}"

      id ->
        {schema, id}
    end
  end

  def record!(other),
    do: raise(ArgumentError, "a grant is on a record (on:), not #{inspect(other)}")

  # The permissions the role gives on the record: a role of the policy, with
  # those it implies, or a role the record defines.
  defp role_permissions!(ctx, policy, resource, role) when is_atom(role) do
    if not Map.has_key?(policy.__sekisho__(:roles), role) do
      raise ArgumentError,
            "#{inspect(role)} is not a role of #{inspect(policy)}: " <>
              inspect(Map.keys(policy.__sekisho__(:roles)))
    end

    Model.role_permissions(ctx.model, resource.__struct__, role)
  end

  defp role_permissions!(ctx, policy, resource, name) when is_binary(name) do
    if not policy.__sekisho__(:custom_roles) do
      raise ArgumentError, "#{inspect(policy)} has no custom_roles, so no role #{inspect(name)}"
    end

    case Sekisho.Roles.get(ctx, resource, name) do
      %Role{} = role -> Enum.map(role.permissions, &String.to_existing_atom/1)
      nil -> raise ArgumentError, "#{inspect(name)} is not a role of #{inspect(resource)}"
    end
  end

  defp grantee!(ctx, policy, to) do
    {kind, type, id} =
      case to do
        :link ->
          {:link, "link", nil}

        %{__struct__: schema} = record ->
          kind = if schema in ctx.model.config.groups, do: :group, else: :user
          {kind, schema.__schema__(:source), Map.fetch!(record, Model.primary_key(schema))}
      end

    kinds = policy.__sekisho__(:grant_to).kinds

    if kind not in kinds do
      raise ArgumentError, "#{inspect(policy)} grants to #{inspect(kinds)}, not to a #{kind}"
    end

    {kind, type, id}
  end

  defp link_role!(_ctx, policy, :link, role) when is_binary(role),
    do:
      raise(
        ArgumentError,
        "#{inspect(policy)} grants a link a role of its own, not #{inspect(role)}"
      )

  defp link_role!(ctx, policy, :link, role) do
    case policy.__sekisho__(:grant_to).link_up_to do
      nil ->
        :ok

      up_to ->
        schema = policy.__sekisho__(:schema)

        if role not in Model.implied(ctx.model, schema, up_to) do
          raise ArgumentError,
                "#{inspect(policy)} grants a link up to #{inspect(up_to)}, not #{inspect(role)}"
        end
    end
  end

  defp link_role!(_ctx, _policy, _kind, _role), do: :ok

  ## Rows

  defp insert(ctx, :link, grant) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    with {:ok, grant} <- ctx.model.config.repo.insert(%{grant | token_hash: Context.hash(token)}) do
      {:ok, %{grant | token: token}}
    end
  end

  defp insert(ctx, _kind, grant) do
    ctx.model.config.repo.insert(grant,
      on_conflict: {:replace, [:expires_at, :granted_by_id]},
      conflict_target: [:resource_type, :resource_id, :actor_type, :actor_id, :role],
      returning: true
    )
  end

  @doc false
  def broadcast(ctx, grant, event) do
    if pubsub = ctx.model.config.pubsub do
      message =
        {:sekisho, event,
         Map.take(grant, [:resource_type, :resource_id, :actor_type, :actor_id, :role])}

      Phoenix.PubSub.broadcast(pubsub, "sekisho", message)

      Phoenix.PubSub.broadcast(
        pubsub,
        "sekisho:#{grant.resource_type}:#{grant.resource_id}",
        message
      )
    end

    :ok
  end
end
