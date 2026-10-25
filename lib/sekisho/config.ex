defmodule Sekisho.Config do
  @moduledoc false
  # The options of `use Sekisho`, checked when the module compiles. The repo
  # is checked with the module's own functions (`Sekisho.__before_compile__/1`):
  # it is `repo:`, or the module's `repo/0`.

  defstruct [
    :repo,
    :sources,
    :pubsub,
    policies: [],
    groups: [],
    deny_as: :forbidden,
    tables: "sekisho"
  ]

  @keys [:repo, :policies, :sources, :groups, :pubsub, :deny_as, :tables]

  def new!(opts) do
    case Keyword.keys(opts) -- @keys do
      [] -> :ok
      unknown -> raise ArgumentError, "use Sekisho does not take #{inspect(unknown)}"
    end

    config = struct!(__MODULE__, opts)

    if config.deny_as not in [:forbidden, :not_found],
      do: raise(ArgumentError, "deny_as: is :forbidden or :not_found")

    Sekisho.Tables.check!(config.tables)
    config
  end
end
