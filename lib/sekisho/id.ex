defmodule Sekisho.Id do
  @moduledoc false
  # The id of a record of your app, in sekisho_grants: an integer (bigint
  # columns) or a UUID (uuid columns), as the migration made them from your
  # repo's primary key.

  use Ecto.Type

  @impl true
  def type, do: :any

  @impl true
  def cast(id) when is_integer(id), do: {:ok, id}
  def cast(id) when is_binary(id), do: Ecto.UUID.cast(id)
  def cast(_id), do: :error

  @impl true
  def dump(id) when is_integer(id), do: {:ok, id}
  def dump(<<_::128>> = id), do: {:ok, id}
  def dump(id) when is_binary(id), do: Ecto.UUID.dump(id)
  def dump(_id), do: :error

  @impl true
  def load(id) when is_integer(id), do: {:ok, id}
  def load(<<_::128>> = id), do: Ecto.UUID.load(id)
  def load(_id), do: :error
end
