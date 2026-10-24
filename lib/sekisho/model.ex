defmodule Sekisho.Model do
  @moduledoc false
  # Every policy of a permissions module, checked together: the relations,
  # the roles they name, and that no two schemas derive from each other. Built
  # the first time the module is asked, and kept in :persistent_term.

  defstruct [:root, :config, policies: %{}, types: %{}]

  @type t :: %__MODULE__{}

  @spec get(module()) :: t()
  def get(root) do
    key = {__MODULE__, root}

    case :persistent_term.get(key, nil) do
      nil ->
        model = build!(root)
        :persistent_term.put(key, model)
        model

      model ->
        model
    end
  end

  @doc false
  # Built again, for a test that changes the policies.
  def reset(root), do: :persistent_term.erase({__MODULE__, root})

  @spec build!(module()) :: t()
  def build!(root) do
    config = root.__sekisho__(:config)

    policies =
      Map.new(config.policies, fn policy ->
        Code.ensure_loaded!(policy)

        if not function_exported?(policy, :__sekisho__, 1),
          do: raise(ArgumentError, "#{inspect(policy)} is not a Sekisho.Policy")

        {policy.__sekisho__(:schema), policy}
      end)

    if map_size(policies) != length(config.policies),
      do: raise(ArgumentError, "#{inspect(root)} has two policies for one schema")

    types = Map.new(policies, fn {schema, _policy} -> {schema, schema.__schema__(:source)} end)
    model = %__MODULE__{root: root, config: config, policies: policies, types: types}
    validate!(model)
    model
  end

  ## The parts of a policy

  def policy!(model, schema) do
    case Map.fetch(model.policies, schema) do
      {:ok, policy} -> policy
      :error -> raise ArgumentError, "#{inspect(model.root)} has no policy for #{inspect(schema)}"
    end
  end

  def type(model, schema), do: Map.fetch!(model.types, schema)

  def primary_key(schema) do
    case schema.__schema__(:primary_key) do
      [key] ->
        key

      keys ->
        raise ArgumentError, "#{inspect(schema)} needs one primary key, not #{inspect(keys)}"
    end
  end

  def permissions(model, schema), do: policy!(model, schema).__sekisho__(:permissions)
  def roles(model, schema), do: policy!(model, schema).__sekisho__(:roles)

  # The roles that give the permission.
  def roles_with(model, schema, permission) do
    for {role, perms} <- roles(model, schema), permission in perms, do: role
  end

  # The roles whose holders hold one of these: the roles themselves, and those
  # they derive from on the same record, to the end.
  def implying(model, schema, roles) do
    derives = same_derives(model, schema)
    grow(MapSet.new(roles), fn set -> for {role, from} <- derives, role in set, do: from end)
  end

  # The roles that holding this one gives, on the same record.
  def implied(model, schema, role) do
    derives = same_derives(model, schema)
    grow(MapSet.new([role]), fn set -> for {to, from} <- derives, from in set, do: to end)
  end

  # The roles that holding any of these gives, on the same record.
  def implied_all(model, schema, roles) do
    Enum.reduce(roles, MapSet.new(), &MapSet.union(&2, implied(model, schema, &1)))
  end

  # The permissions a role gives, with the roles it implies.
  def role_permissions(model, schema, role) do
    roles = roles(model, schema)

    model
    |> implied(schema, role)
    |> Enum.flat_map(&Map.fetch!(roles, &1))
    |> Enum.uniq()
  end

  # {role, relation, role on the related record}, for the roles given.
  def related_derives(model, schema, roles) do
    for {role, {relation, other}} <- policy!(model, schema).__sekisho__(:derives),
        role in roles,
        do: {role, relation, other}
  end

  defp same_derives(model, schema) do
    for {role, from} <- policy!(model, schema).__sekisho__(:derives),
        is_atom(from),
        do: {role, from}
  end

  defp grow(set, step) do
    next = MapSet.union(set, MapSet.new(step.(set)))
    if MapSet.equal?(next, set), do: set, else: grow(next, step)
  end

  # How a relation is followed: the schema's belongs_to, or a query of the
  # sources.
  def relation!(model, schema, name) do
    case schema.__schema__(:association, name) do
      %Ecto.Association.BelongsTo{owner_key: key, related: related} ->
        {:belongs_to, key, related}

      nil ->
        case Map.fetch(policy!(model, schema).__sekisho__(:relations), name) do
          {:ok, related} -> {:source, related}
          :error -> raise ArgumentError, relation_error(schema, name)
        end

      other ->
        raise ArgumentError,
              "#{inspect(schema)}'s #{inspect(name)} is a #{inspect(other.__struct__)}: " <>
                "derive follows a belongs_to, or a relation of your sources"
    end
  end

  defp relation_error(schema, name) do
    "#{inspect(schema)} has no belongs_to #{inspect(name)}, and its policy declares no " <>
      "relation #{inspect(name)}"
  end

  ## The checks of the whole

  defp validate!(model) do
    edges =
      for {schema, policy} <- model.policies,
          {role, {relation, other}} <- policy.__sekisho__(:derives) do
        {kind, related} = follow!(model, schema, relation)
        related_policy = policy!(model, related)

        if not Map.has_key?(related_policy.__sekisho__(:roles), other) do
          raise ArgumentError,
                "#{inspect(policy)}: #{inspect(role)} derives from #{inspect(other)} on " <>
                  "#{inspect(relation)}, which is not a role of #{inspect(related_policy)}"
        end

        if related == schema and kind == :source do
          raise ArgumentError,
                "#{inspect(policy)}: #{inspect(relation)} relates #{inspect(schema)} to itself through " <>
                  "your sources; a relation to the same schema is a belongs_to"
        end

        if related == schema and role != other do
          raise ArgumentError,
                "#{inspect(policy)}: on a relation to the same schema (#{inspect(relation)}), " <>
                  "a role derives from itself (derive #{inspect(other)}, from: " <>
                  "{#{inspect(relation)}, #{inspect(other)}})"
        end

        {schema, related}
      end

    acyclic!(Enum.reject(edges, fn {from, to} -> from == to end))
  end

  defp follow!(model, schema, relation) do
    case relation!(model, schema, relation) do
      {:belongs_to, _key, related} -> {:belongs_to, related}
      {:source, related} -> {:source, related}
    end
  end

  # Schemas that derive from each other would never end.
  defp acyclic!(edges) do
    graph = Enum.group_by(edges, &elem(&1, 0), &elem(&1, 1))

    Enum.each(Map.keys(graph), fn start -> visit(graph, start, [start]) end)
  end

  defp visit(graph, node, path) do
    for next <- Map.get(graph, node, []) do
      if next in path do
        cycle = Enum.map_join(Enum.reverse([next | path]), " -> ", &inspect/1)
        raise ArgumentError, "roles derive in a circle: #{cycle}"
      end

      visit(graph, next, [next | path])
    end
  end
end
