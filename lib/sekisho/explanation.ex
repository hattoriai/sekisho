defmodule Sekisho.Explanation do
  @moduledoc """
  Why a permission is allowed or not: what `explain/3` returns.

  `reasons` lists everything that allows it, each one of:

    * `{:allow}`: a rule of the policy (`allow/2`);
    * `{:grant, role, grant}`: a role granted on the record (`Sekisho.Grant`);
    * `{:source, role}`: a role from your sources;
    * `{:related, role, relation, record, reasons}`: a role derived from one
      held on a related record, and why that one is held.

  `denied` is true when `deny/2` refuses it, whatever the reasons.

      iex> MyApp.Permissions.explain(scope, :update, document)
      #Sekisho.Explanation<allowed :update on MyApp.Docs.Document 7
        holds :editor through :folder: MyApp.Docs.Folder 3
          holds :viewer through :parent: MyApp.Docs.Folder 1
            holds :owner: granted to users 5>
  """

  defstruct [:permission, :resource, allowed?: false, denied: false, reasons: []]

  @type reason ::
          {:allow}
          | {:grant, atom(), Sekisho.Grant.t()}
          | {:source, atom()}
          | {:related, atom(), atom(), struct(), [reason()]}

  @type t :: %__MODULE__{
          permission: atom(),
          resource: struct(),
          allowed?: boolean(),
          denied: boolean(),
          reasons: [reason()]
        }

  @doc "The explanation as lines of text, for a log or a test's failure."
  @spec lines(t()) :: [String.t()]
  def lines(%__MODULE__{} = explanation) do
    head =
      if explanation.allowed?,
        do: "allowed #{inspect(explanation.permission)} on #{describe(explanation.resource)}",
        else:
          "not allowed #{inspect(explanation.permission)} on #{describe(explanation.resource)}"

    body =
      cond do
        explanation.denied ->
          ["  denied by a rule of the policy (deny/2)" | reasons(explanation.reasons, 1)]

        explanation.reasons == [] ->
          ["  no rule allows it, and no role that gives it is held"]

        true ->
          reasons(explanation.reasons, 1)
      end

    [head | body]
  end

  defp reasons(reasons, depth), do: Enum.flat_map(reasons, &reason(&1, depth))

  defp reason({:allow}, depth), do: [indent(depth) <> "a rule of the policy (allow/2)"]

  defp reason({:grant, role, grant}, depth) do
    to =
      if grant.actor_type == "link",
        do: "anyone with the link",
        else: "#{grant.actor_type} #{grant.actor_id}"

    [indent(depth) <> "holds #{inspect(role)}: granted to #{to}"]
  end

  defp reason({:source, role}, depth),
    do: [indent(depth) <> "holds #{inspect(role)}: from your sources"]

  defp reason({:related, role, relation, record, why}, depth) do
    [
      indent(depth) <> "holds #{inspect(role)} through #{inspect(relation)}: #{describe(record)}"
      | reasons(why, depth + 1)
    ]
  end

  defp indent(depth), do: String.duplicate("  ", depth)

  defp describe(%{__struct__: schema} = record) do
    [key] = schema.__schema__(:primary_key)
    "#{inspect(schema)} #{inspect(Map.get(record, key))}"
  end

  defimpl Inspect do
    def inspect(explanation, _opts) do
      "#Sekisho.Explanation<" <> Enum.join(Sekisho.Explanation.lines(explanation), "\n") <> ">"
    end
  end
end
