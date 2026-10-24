defmodule Sekisho.Config do
  @moduledoc false
  # The options of `use Sekisho`, checked when the module compiles.

  defstruct [:repo, :sources, :pubsub, policies: [], groups: [], deny_as: :forbidden]

  @keys [:repo, :policies, :sources, :groups, :pubsub, :deny_as]

  def new!(opts) do
    case Keyword.keys(opts) -- @keys do
      [] -> :ok
      unknown -> raise ArgumentError, "use Sekisho does not take #{inspect(unknown)}"
    end

    config = struct!(__MODULE__, opts)

    if is_nil(config.repo), do: raise(ArgumentError, "use Sekisho needs repo:")
    if config.policies == [], do: raise(ArgumentError, "use Sekisho needs policies:")

    if config.deny_as not in [:forbidden, :not_found],
      do: raise(ArgumentError, "deny_as: is :forbidden or :not_found")

    config
  end
end
