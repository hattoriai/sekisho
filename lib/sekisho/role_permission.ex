defmodule Sekisho.RolePermission do
  @moduledoc """
  A permission a role of `Sekisho.Role` gives: a row of
  `sekisho_role_permissions`. `Sekisho.Role`'s `permissions` lists them.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sekisho_role_permissions" do
    belongs_to :role, Sekisho.Role
    field :permission, :string
  end
end
