defmodule Sekisho.Tables do
  @moduledoc false
  # The names of Sekisho's tables: sekisho_grants, sekisho_roles and
  # sekisho_role_permissions, or the same with another start (`tables:`), so
  # a library keeps its grants apart from its host's.
  #
  # The schemas (Sekisho.Grant, Sekisho.Role, Sekisho.RolePermission) name
  # the default tables; a query names the table of its permissions module
  # (`from/2`) and a row to insert carries it in its metadata (`put/2`).

  alias Sekisho.{Grant, Role, RolePermission}

  # The longest name Ecto makes from a table (an index of sekisho_grants)
  # stays within the 64 characters MySQL takes.
  @max 16

  def check!(tables) do
    if not (is_binary(tables) and Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, tables) and
              byte_size(tables) <= @max) do
      raise ArgumentError,
            "tables: is the start of the names of Sekisho's tables, in lowercase letters, " <>
              "digits and _, up to #{@max} characters, not #{inspect(tables)}"
    end

    tables
  end

  def name(tables, :grants), do: tables <> "_grants"
  def name(tables, :roles), do: tables <> "_roles"
  def name(tables, :role_permissions), do: tables <> "_role_permissions"

  # The source of a query: `from g in Tables.from(ctx, :grants)`.
  def from(ctx, table), do: {name(tables(ctx), table), schema(table)}

  # A row, to insert in the tables of the permissions module.
  def put(%schema{} = row, ctx), do: Ecto.put_meta(row, source: name(tables(ctx), table(schema)))

  # The name of the unique index of a role's name on its record.
  def role_name_index(ctx),
    do: :"#{name(tables(ctx), :roles)}_resource_type_resource_id_name_index"

  defp tables(%{model: %{config: config}}), do: config.tables

  defp schema(:grants), do: Grant
  defp schema(:roles), do: Role
  defp schema(:role_permissions), do: RolePermission

  defp table(Grant), do: :grants
  defp table(Role), do: :roles
  defp table(RolePermission), do: :role_permissions
end
