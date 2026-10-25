defmodule Sekisho.Roles do
  @moduledoc false
  # create_role/4, update_role/3, delete_role/2 and roles/2 of a permissions
  # module: the roles a record defines for itself (custom_roles).
  #
  # Each is checked as a grant is: the permission grant_to names (`by:`), and
  # every permission the role gives, so no one makes a role above their own.

  import Ecto.Query

  alias Sekisho.{Context, Grant, Grants, Model, Role, RolePermission, Tables}

  def create(root, scope, resource, name, permissions, opts) do
    ctx = Context.new(root, scope)
    {schema, id} = Grants.record!(resource)
    policy = custom!(ctx, schema)
    name = name!(policy, name)
    permissions = permissions!(policy, permissions)

    with :ok <- Grants.check(ctx, opts, resource, permissions) do
      %Role{
        resource_type: Model.type(ctx.model, schema),
        resource_id: id,
        name: name,
        permission_rows: rows(ctx, permissions)
      }
      |> Tables.put(ctx)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint(:name,
        name: Tables.role_name_index(ctx),
        message: "is already a role of this record"
      )
      |> ctx.repo.insert()
      |> with_permissions()
      |> tap(&notify(ctx, &1))
    end
  end

  def update(root, scope, %Role{} = role, permissions, opts) do
    ctx = Context.new(root, scope)
    resource = resource!(ctx, role)
    policy = Model.policy!(ctx.model, resource.__struct__)
    permissions = permissions!(policy, permissions)
    before = Enum.map(role.permissions, &String.to_existing_atom/1)

    # Both what it gave and what it will give: taking a permission away is
    # giving it, too.
    with :ok <- Grants.check(ctx, opts, resource, Enum.uniq(before ++ permissions)) do
      repo = ctx.repo

      role
      |> repo.preload(permission_rows: from(p in Tables.from(ctx, :role_permissions)))
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:permission_rows, rows(ctx, permissions))
      |> repo.update()
      |> with_permissions()
      |> tap(&notify(ctx, &1))
    end
  end

  def delete(root, scope, %Role{} = role, opts) do
    ctx = Context.new(root, scope)
    resource = resource!(ctx, role)
    permissions = Enum.map(role.permissions, &String.to_existing_atom/1)
    repo = ctx.repo

    with :ok <- Grants.check(ctx, opts, resource, permissions) do
      {:ok, _} =
        repo.transaction(fn ->
          repo.delete_all(
            from g in Tables.from(ctx, :grants),
              where:
                g.resource_type == ^role.resource_type and g.resource_id == ^role.resource_id,
              where: g.role == ^role.name
          )

          repo.delete!(role)
        end)

      changed(ctx, role)
      :ok
    end
  end

  def list(root, scope, resource) do
    ctx = Context.new(root, scope)
    {schema, _id} = Grants.record!(resource)
    policy = custom!(ctx, schema)

    with :ok <- Grants.authorize(ctx, policy.__sekisho__(:grant_to).by, resource) do
      roles = ctx.repo.all(from(r in query(ctx, resource), order_by: r.name))
      {:ok, Enum.map(roles, &Role.load_permissions/1)}
    end
  end

  @doc false
  def get(ctx, resource, name) do
    case ctx.repo.one(from r in query(ctx, resource), where: r.name == ^name) do
      nil -> nil
      role -> Role.load_permissions(role)
    end
  end

  # The roles of a record, each with its permissions, in the order given.
  defp query(ctx, %{__struct__: schema} = resource) do
    type = Model.type(ctx.model, schema)
    id = Map.fetch!(resource, Model.primary_key(schema))
    rows = from p in Tables.from(ctx, :role_permissions), order_by: p.id

    from r in Tables.from(ctx, :roles),
      where: r.resource_type == ^type and r.resource_id == ^id,
      preload: [permission_rows: ^rows]
  end

  defp rows(ctx, permissions),
    do: Enum.map(permissions, &Tables.put(%RolePermission{permission: to_string(&1)}, ctx))

  defp with_permissions({:ok, %Role{} = role}), do: {:ok, Role.load_permissions(role)}
  defp with_permissions(other), do: other

  ## Checks

  defp custom!(ctx, schema) do
    policy = Model.policy!(ctx.model, schema)

    if not policy.__sekisho__(:custom_roles),
      do: raise(ArgumentError, "#{inspect(policy)} has no custom_roles")

    policy
  end

  defp name!(policy, name) when is_binary(name) do
    name = String.trim(name)

    cond do
      name == "" ->
        raise ArgumentError, "a role's name is not blank"

      Enum.any?(Map.keys(policy.__sekisho__(:roles)), &(to_string(&1) == name)) ->
        raise ArgumentError, "#{inspect(name)} is a role of #{inspect(policy)} already"

      true ->
        name
    end
  end

  defp permissions!(policy, permissions) do
    declared = policy.__sekisho__(:permissions)

    Enum.map(permissions, fn permission ->
      permission =
        if is_binary(permission), do: to_permission(permission, declared), else: permission

      if permission not in declared do
        raise ArgumentError, "#{inspect(permission)} is not a permission of #{inspect(policy)}"
      end

      permission
    end)
    |> Enum.uniq()
  end

  # A permission from a form: one of the declared, never a new atom.
  defp to_permission(name, declared), do: Enum.find(declared, name, &(to_string(&1) == name))

  defp resource!(ctx, role) do
    {schema, _type} =
      Enum.find(ctx.model.types, fn {_schema, type} -> type == role.resource_type end)

    ctx.repo.get!(schema, role.resource_id)
  end

  defp notify(ctx, {:ok, role}), do: changed(ctx, role)
  defp notify(_ctx, _error), do: :ok

  defp changed(ctx, role) do
    Grants.broadcast(
      ctx,
      %Grant{resource_type: role.resource_type, resource_id: role.resource_id, role: role.name},
      :role_changed
    )
  end
end
