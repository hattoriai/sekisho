defmodule Sekisho.Denied do
  @moduledoc """
  A permission refused: what `authorize/3` returns and `authorize!/3` raises.

  Phoenix answers it with a 403 (`plug_status`), or a 404 with `deny_as:
  :not_found` in `use Sekisho`, so that a record's existence is not told.
  """

  defexception [:permission, :resource, plug_status: 403]

  @type t :: %__MODULE__{
          permission: atom(),
          resource: struct() | module(),
          plug_status: 403 | 404
        }

  @impl true
  def message(%{permission: permission, resource: resource}) do
    "not allowed to #{inspect(permission)} #{describe(resource)}"
  end

  defp describe(%{__struct__: schema} = record) do
    case schema.__schema__(:primary_key) do
      [key] -> "#{inspect(schema)} #{inspect(Map.get(record, key))}"
      _keys -> inspect(schema)
    end
  end

  defp describe(schema), do: inspect(schema)
end
