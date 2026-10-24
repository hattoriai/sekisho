defmodule Sekisho.Role do
  @moduledoc """
  A role a record defines for itself (an org's "Support"): a row of
  `sekisho_roles`, with a name and some of its policy's permissions.

  Made with `create_role/4` of your permissions module, for a policy with
  `custom_roles()`, and granted by its name.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sekisho_roles" do
    field :resource_type, :string
    field :resource_id, Sekisho.Id
    field :name, :string
    field :permissions, {:array, :string}, default: []

    timestamps(type: :utc_datetime_usec)
  end
end
