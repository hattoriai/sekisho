defmodule Sekisho.Test do
  @moduledoc """
  Assertions for your tests, whose failures say why (`explain/3`):

      use Sekisho.Test, permissions: MyApp.Permissions

      assert_allowed scope, :update, post
      refute_allowed scope, :delete, post
      assert_where_allowed Post, scope, :read, [published, mine]

  and a test that your policies are valid together:

      test "the permissions are valid" do
        assert MyApp.Permissions.validate!() == :ok
      end
  """

  import ExUnit.Assertions

  @doc false
  defmacro __using__(opts) do
    quote do
      @sekisho_permissions Keyword.fetch!(unquote(opts), :permissions)
      import Sekisho.Test, only: [assert_allowed: 3, refute_allowed: 3, assert_where_allowed: 4]
    end
  end

  @doc "Asserts the scope has the permission on the resource."
  defmacro assert_allowed(scope, permission, resource) do
    quote do
      Sekisho.Test.__check__(
        @sekisho_permissions,
        unquote(scope),
        unquote(permission),
        unquote(resource),
        true
      )
    end
  end

  @doc "Asserts the scope does not have the permission on the resource."
  defmacro refute_allowed(scope, permission, resource) do
    quote do
      Sekisho.Test.__check__(
        @sekisho_permissions,
        unquote(scope),
        unquote(permission),
        unquote(resource),
        false
      )
    end
  end

  @doc "Asserts `where_allowed/3` gives exactly these records, in any order."
  defmacro assert_where_allowed(queryable, scope, permission, records) do
    quote do
      Sekisho.Test.__list__(
        @sekisho_permissions,
        unquote(queryable),
        unquote(scope),
        unquote(permission),
        unquote(records)
      )
    end
  end

  @doc false
  def __check__(root, scope, permission, resource, expected) do
    if root.allowed?(scope, permission, resource) != expected do
      why =
        case resource do
          %{__struct__: _} ->
            "\n\n" <>
              Enum.join(
                Sekisho.Explanation.lines(root.explain(scope, permission, resource)),
                "\n"
              )

          _schema ->
            ""
        end

      flunk(
        "expected #{if expected, do: "", else: "not "}to be allowed #{inspect(permission)}#{why}"
      )
    end

    true
  end

  @doc false
  def __list__(root, queryable, scope, permission, records) do
    query = root.where_allowed(queryable, scope, permission)
    %Ecto.Query{from: %{source: {_source, schema}}} = query
    [key] = schema.__schema__(:primary_key)
    repo = root.__sekisho__(:config).repo

    got = query |> repo.all() |> MapSet.new(&Map.fetch!(&1, key))
    want = MapSet.new(records, &Map.fetch!(&1, key))

    assert got == want,
           "where_allowed #{inspect(permission)}: " <>
             "missing #{inspect(MapSet.to_list(MapSet.difference(want, got)))}, " <>
             "unexpected #{inspect(MapSet.to_list(MapSet.difference(got, want)))}"
  end
end
