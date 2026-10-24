defmodule Sekisho.Context do
  @moduledoc false
  # Who asks, once for each question: the actor, its table and id, and the
  # links it holds.

  alias Sekisho.Model

  defstruct [:root, :model, :scope, :actor, :actor_type, :actor_id, token_hashes: [], now: nil]

  def new(root, scope) do
    model = Model.get(root)
    actor = root.actor(scope)
    tokens = root.link_tokens(scope) || []

    {type, id} =
      case actor do
        %{__struct__: schema} = actor when is_atom(schema) ->
          if function_exported?(schema, :__schema__, 1),
            do: {schema.__schema__(:source), Map.fetch!(actor, Model.primary_key(schema))},
            else: {nil, nil}

        _other ->
          {nil, nil}
      end

    %__MODULE__{
      root: root,
      model: model,
      scope: scope,
      actor: actor,
      actor_type: type,
      actor_id: id,
      token_hashes: Enum.map(tokens, &hash/1),
      now: DateTime.utc_now()
    }
  end

  def hash(token), do: :crypto.hash(:sha256, token)
end
