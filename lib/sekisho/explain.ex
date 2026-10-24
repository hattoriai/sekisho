defmodule Sekisho.Explain do
  @moduledoc false
  # Why the actor holds one of the roles on a record: the same paths as
  # Sekisho.Condition, followed record by record, with what was found on each.

  import Ecto.Query

  alias Sekisho.{Call, Grant, Model}

  def holds(_ctx, _record, [], _visited), do: []

  def holds(ctx, %{__struct__: schema} = record, roles, visited) do
    key = Model.primary_key(schema)
    id = Map.fetch!(record, key)

    if {schema, id} in visited do
      []
    else
      visited = [{schema, id} | visited]
      roles = Model.implying(ctx.model, schema, roles)
      names = Enum.map(roles, &to_string/1)

      granted(ctx, schema, id, names) ++
        sourced(ctx, schema, id, names) ++ related(ctx, record, roles, visited)
    end
  end

  defp granted(ctx, schema, id, names) do
    type = Model.type(ctx.model, schema)
    now = ctx.now

    query =
      from g in Grant,
        where: g.resource_type == ^type and g.resource_id == ^id and g.role in ^names,
        where: is_nil(g.expires_at) or g.expires_at > ^now

    query
    |> ctx.model.config.repo.all()
    |> Enum.filter(&mine?(ctx, &1))
    |> Enum.map(&{:grant, String.to_existing_atom(&1.role), &1})
  end

  # A grant of the actor: to itself, to one of its groups, to a link it holds.
  defp mine?(ctx, %Grant{actor_type: "link"} = grant), do: grant.token_hash in ctx.token_hashes

  defp mine?(ctx, %Grant{} = grant) do
    cond do
      is_nil(ctx.actor_id) -> false
      grant.actor_type == ctx.actor_type and grant.actor_id == ctx.actor_id -> true
      true -> member?(ctx, grant)
    end
  end

  defp member?(ctx, grant) do
    Enum.any?(ctx.model.config.groups, fn group ->
      group.__schema__(:source) == grant.actor_type and
        case Call.optional(ctx.model.config.sources, :members, [group]) do
          nil ->
            false

          members ->
            actor_id = ctx.actor_id
            group_id = grant.actor_id

            ctx.model.config.repo.exists?(
              from m in subquery(members),
                where: m.actor_id == ^actor_id and m.group_id == ^group_id
            )
        end
    end)
  end

  defp sourced(ctx, schema, id, names) do
    with actor_id when not is_nil(actor_id) <- ctx.actor_id,
         query when not is_nil(query) <- Call.optional(ctx.model.config.sources, :roles, [schema]) do
      from(s in subquery(query),
        where: s.actor_id == ^actor_id and s.resource_id == ^id and s.role in ^names,
        select: s.role
      )
      |> ctx.model.config.repo.all()
      |> Enum.uniq()
      |> Enum.map(&{:source, to_role(&1)})
    else
      _none -> []
    end
  end

  # Each relation once: what is held on the related record, and the strongest
  # role it gives here (the one that implies the most).
  defp related(ctx, %{__struct__: schema} = record, roles, visited) do
    ctx.model
    |> Model.related_derives(schema, roles)
    |> Enum.group_by(fn {_role, relation, _other} -> relation end)
    |> Enum.flat_map(fn {relation, derives} ->
      others = derives |> Enum.map(&elem(&1, 2)) |> Enum.uniq()

      for related <- related_records(ctx, record, relation),
          why = holds(ctx, related, others, visited),
          why != [],
          do: {:related, strongest(ctx, schema, derives, related, why), relation, related, why}
    end)
  end

  defp strongest(ctx, schema, derives, related, why) do
    held_there = Model.implied_all(ctx.model, related.__struct__, held(why))
    given = for {role, _relation, other} <- derives, other in held_there, do: role
    Enum.max_by(given, &MapSet.size(Model.implied(ctx.model, schema, &1)))
  end

  defp held(reasons), do: Enum.map(reasons, &elem(&1, 1))

  defp related_records(ctx, %{__struct__: schema} = record, relation) do
    repo = ctx.model.config.repo

    case Model.relation!(ctx.model, schema, relation) do
      {:belongs_to, key, related} ->
        case Map.fetch!(record, key) do
          nil -> []
          id -> List.wrap(repo.get(related, id))
        end

      {:source, related} ->
        query = Call.optional(ctx.model.config.sources, :relation, [schema, relation])
        id = Map.fetch!(record, Model.primary_key(schema))
        related_key = Model.primary_key(related)
        ids = from r in subquery(query), where: r.resource_id == ^id, select: r.related_id
        repo.all(from y in related, where: field(y, ^related_key) in subquery(ids))
    end
  end

  defp to_role(role) when is_atom(role), do: role
  defp to_role(role) when is_binary(role), do: String.to_existing_atom(role)
end
