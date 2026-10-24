defmodule Sekisho.Role do
  @moduledoc """
  A role a record defines for itself (an org's "Support"): a row of
  `sekisho_roles`, with a name and some of its policy's permissions
  (`permissions`, kept in `sekisho_role_permissions`).

  Made with `create_role/4` of your permissions module, for a policy with
  `custom_roles()`, and granted by its name.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sekisho_roles" do
    field :resource_type, :string
    field :resource_id, Sekisho.Id
    field :name, :string
    field :permissions, {:array, :string}, virtual: true, default: []
    has_many :permission_rows, Sekisho.RolePermission, on_replace: :delete

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  # `permissions` from the rows, once they are loaded.
  def load_permissions(%__MODULE__{permission_rows: rows} = role) when is_list(rows),
    do: %{role | permissions: Enum.map(rows, & &1.permission)}
end
