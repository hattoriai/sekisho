defmodule Sekisho.Condition do
  @moduledoc false
  # A permission, as one condition on a schema: true, false, or a dynamic
  # whose first binding is the schema.
  #
  #     (allow OR id IN (the records on which a role that gives it is held))
  #       AND NOT deny
  #
  # The records on which a role is held are a set of ids: the union of every
  # path to them, each a query on its own indexes (the grants of the actor,
  # the rows of your sources, the records under a related record that holds
  # a role, the descendants of a record through a relation to the same
  # schema). A set, not a chain of OR, so the database estimates and hashes
  # each part.

  import Ecto.Query

  alias Sekisho.{Call, Context, Grant, Model}

  @type t :: boolean() | Ecto.Query.DynamicExpr.t()

  @spec build(Context.t(), module(), atom()) :: t()
  def build(ctx, schema, permission) do
    policy = Model.policy!(ctx.model, schema)

    if permission not in policy.__sekisho__(:permissions) do
      raise ArgumentError,
            "#{inspect(permission)} is not a permission of #{inspect(policy)}: " <>
              inspect(policy.__sekisho__(:permissions))
    end

    allowed = rule(policy, :allow, ctx.actor, permission)
    denied = rule(policy, :deny, ctx.actor, permission)

    # A role that gives it, a custom role that gives it, or what gives it on
    # a related record.
    paths =
      paths(ctx, schema, Model.roles_with(ctx.model, schema, permission)) ++
        custom(ctx, schema, permission) ++
        Enum.flat_map(Model.permission_derives(ctx.model, schema, permission), fn {relation,
                                                                                   other} ->
          List.wrap(related(ctx, schema, relation, [other]))
        end)

    both(either(allowed, within(schema, paths)), negate(denied))
  end

  defp within(_schema, []), do: false

  defp within(schema, paths) do
    key = Model.primary_key(schema)
    ids = from(u in subquery(union_all(paths)), select: u.id)
    dynamic([x], field(x, ^key) in subquery(ids))
  end

  # The ids of the records of the schema on which the actor holds one of the
  # roles, as a query of one column, or nil when no path can hold one.
  defp ids(_ctx, _schema, []), do: nil

  defp ids(ctx, schema, roles) do
    case paths(ctx, schema, roles) do
      [] -> nil
      paths -> from(u in subquery(union_all(paths)), select: u.id)
    end
  end

  # Every path to the records that hold one of the roles: queries that select
  # %{id: ...}.
  # No role gives the permission: no path, so a rule alone answers (and a
  # "no" needs no record).
  defp paths(_ctx, _schema, []), do: []

  defp paths(ctx, schema, roles) do
    roles = Model.implying(ctx.model, schema, roles)
    derives = Model.related_derives(ctx.model, schema, roles)
    {down, across} = Enum.split_with(derives, &self_relation?(ctx, schema, &1))
    here = held_here(ctx, schema, roles, across)

    # A role that passes down a relation to the same schema (a folder's
    # parent) is held under any record that holds it: a recursive query from
    # those records.
    trees =
      down
      |> Enum.group_by(fn {_role, relation, _other} -> relation end, fn {role, _, _} -> role end)
      |> Enum.map(fn {relation, passed} ->
        {:belongs_to, key, ^schema} = Model.relation!(ctx.model, schema, relation)
        seed_roles = Model.implying(ctx.model, schema, passed)
        seed_across = Model.related_derives(ctx.model, schema, seed_roles) -- down
        seed = held_here(ctx, schema, seed_roles, seed_across)
        {MapSet.equal?(seed_roles, roles), descendants(schema, key, seed)}
      end)
      |> Enum.reject(fn {_whole, tree} -> is_nil(tree) end)

    case trees do
      # Every role passes down: the tree starts from the records that hold one
      # themselves, so it is every answer.
      [{true, tree}] -> [tree]
      trees -> here ++ Enum.map(trees, &elem(&1, 1))
    end
  end

  defp self_relation?(ctx, schema, {_role, relation, _other}) do
    match?({:belongs_to, _key, ^schema}, Model.relation!(ctx.model, schema, relation))
  end

  # Held on the record itself (grants, sources), or derived across a relation
  # to another schema. The roles derived through one relation are asked of it
  # at once: holding any of them there gives one of these here.
  defp held_here(ctx, schema, roles, across) do
    names = Enum.map(roles, &to_string/1)

    related =
      across
      |> Enum.group_by(fn {_role, relation, _other} -> relation end, fn {_, _, other} -> other end)
      |> Enum.map(fn {relation, others} -> related(ctx, schema, relation, Enum.uniq(others)) end)

    Enum.reject([grants(ctx, schema, names), sourced(ctx, schema, names) | related], &is_nil/1)
  end

  ## Held on the record: grants and sources

  defp grants(ctx, schema, names) do
    case grantees(ctx) do
      false ->
        nil

      who ->
        type = Model.type(ctx.model, schema)
        now = ctx.now

        from g in Grant,
          where: g.resource_type == ^type and g.role in ^names,
          where: is_nil(g.expires_at) or g.expires_at > ^now,
          where: ^who,
          select: %{id: g.resource_id}
    end
  end

  # The grantees the actor is: itself, its groups, the links it holds.
  defp grantees(ctx) do
    user =
      if ctx.actor_id do
        dynamic([g], g.actor_type == ^ctx.actor_type and g.actor_id == ^ctx.actor_id)
      else
        false
      end

    groups =
      if ctx.actor_id do
        ctx.model.config.groups
        |> Enum.map(&in_group(ctx, &1))
        |> Enum.reduce(false, &either(&2, &1))
      else
        false
      end

    links =
      case ctx.token_hashes do
        [] -> false
        hashes -> dynamic([g], g.actor_type == "link" and g.token_hash in ^hashes)
      end

    user |> either(groups) |> either(links)
  end

  defp in_group(ctx, group) do
    case Call.optional(ctx.model.config.sources, :members, [group]) do
      nil ->
        raise ArgumentError,
              "#{inspect(group)} is a group of #{inspect(ctx.root)}, and its sources have no " <>
                "members/1 for it"

      members ->
        type = group.__schema__(:source)
        actor_id = ctx.actor_id
        ids = from m in subquery(members), where: m.actor_id == ^actor_id, select: m.group_id
        dynamic([g], g.actor_type == ^type and g.actor_id in subquery(ids))
    end
  end

  defp sourced(ctx, schema, names) do
    with id when not is_nil(id) <- ctx.actor_id,
         query when not is_nil(query) <- Call.optional(ctx.model.config.sources, :roles, [schema]) do
      from s in subquery(query),
        # Strings: a role the app's query writes as a literal is typed binary,
        # and SQLite never finds text in a blob.
        where: s.actor_id == ^id and type(s.role, :string) in ^names,
        select: %{id: s.resource_id}
    else
      _none -> nil
    end
  end

  ## Roles a record defines (custom_roles): granted by name, their
  ## permissions in sekisho_roles

  defp custom(ctx, schema, permission) do
    with true <- Model.custom_roles?(ctx.model, schema),
         who when who != false <- grantees(ctx) do
      type = Model.type(ctx.model, schema)
      name = to_string(permission)
      now = ctx.now

      [
        from(g in Grant,
          join: r in Sekisho.Role,
          on:
            r.resource_type == g.resource_type and r.resource_id == g.resource_id and
              r.name == g.role,
          join: p in Sekisho.RolePermission,
          on: p.role_id == r.id and p.permission == ^name,
          where: g.resource_type == ^type,
          where: is_nil(g.expires_at) or g.expires_at > ^now,
          where: ^who,
          select: %{id: g.resource_id}
        )
      ]
    else
      _none -> []
    end
  end

  ## Derived from a related record

  defp related(ctx, schema, relation, others) do
    case Model.relation!(ctx.model, schema, relation) do
      {:belongs_to, key, related} ->
        with ids when not is_nil(ids) <- related_ids(ctx, related, others) do
          id = Model.primary_key(schema)
          from y in schema, where: field(y, ^key) in subquery(ids), select: %{id: field(y, ^id)}
        end

      {:source, related} ->
        query =
          Call.optional(ctx.model.config.sources, :relation, [schema, relation]) ||
            raise ArgumentError,
                  "#{inspect(schema)}'s relation #{inspect(relation)} needs relation/2 in the " <>
                    "sources of #{inspect(ctx.root)}"

        with ids when not is_nil(ids) <- related_ids(ctx, related, others) do
          from r in subquery(query),
            where: r.related_id in subquery(ids),
            select: %{id: r.resource_id}
        end
    end
  end

  # The ids of the related records where one of these is held: a role (and
  # what derives it), or a permission (its whole condition, rules included).
  defp related_ids(ctx, related, others) do
    {roles, permissions} = Enum.split_with(others, &Model.role?(ctx.model, related, &1))
    key = Model.primary_key(related)

    by_permission =
      for permission <- permissions do
        case build(ctx, related, permission) do
          false -> nil
          true -> from(y in related, select: field(y, ^key))
          condition -> from(y in related, where: ^condition, select: field(y, ^key))
        end
      end

    case Enum.reject([ids(ctx, related, roles) | by_permission], &is_nil/1) do
      [] -> nil
      queries -> union_all(queries)
    end
  end

  # The records under those of the seed, through a belongs_to to the same
  # schema: the seed, its children, theirs. UNION, not UNION ALL, so a loop in
  # the data ends.
  defp descendants(_schema, _key, []), do: nil

  defp descendants(schema, key, seed) do
    id = Model.primary_key(schema)
    start = from s in subquery(union_all(seed)), select: %{id: s.id}

    step =
      from c in schema,
        join: t in "sekisho_tree",
        on: field(c, ^key) == t.id,
        select: %{id: field(c, ^id)}

    cte = union(start, ^step)

    "sekisho_tree"
    |> recursive_ctes(true)
    |> with_cte("sekisho_tree", as: ^cte)
    |> select([t], %{id: t.id})
  end

  defp union_all([query]), do: query
  defp union_all([query | rest]), do: Enum.reduce(rest, query, &union_all(&2, ^&1))

  ## Rules

  defp rule(policy, function, actor, permission) do
    case Call.optional(policy, function, [actor, permission]) do
      nil -> false
      result when is_boolean(result) -> result
      %Ecto.Query.DynamicExpr{} = condition -> condition
      other -> raise ArgumentError, "#{inspect(policy)}.#{function}/2 returned #{inspect(other)}"
    end
  end

  ## Conditions, simplified when one side is known

  def either(true, _b), do: true
  def either(_a, true), do: true
  def either(false, b), do: b
  def either(a, false), do: a
  def either(a, b), do: dynamic(^a or ^b)

  def both(false, _b), do: false
  def both(_a, false), do: false
  def both(true, b), do: b
  def both(a, true), do: a
  def both(a, b), do: dynamic(^a and ^b)

  def negate(true), do: false
  def negate(false), do: true
  def negate(a), do: dynamic(not (^a))
end
