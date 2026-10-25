defmodule Sekisho.ConfigTest do
  # What `use Sekisho` and `use Sekisho.Migrations` refuse when they compile.
  use ExUnit.Case, async: true

  test "a permissions module names its repo, with repo: or a repo/0" do
    assert SekishoTest.Permissions.repo() == SekishoTest.Repo
    assert SekishoTest.LibraryPermissions.repo() == SekishoTest.Repo
  end

  test "a permissions module without a repo does not compile" do
    assert_raise ArgumentError, ~r/needs repo:, or a repo\/0/, fn ->
      compile("""
      defmodule Sekisho.ConfigTest.NoRepo do
        use Sekisho, policies: []
        def actor(_scope), do: nil
      end
      """)
    end
  end

  test "a permissions module with repo: and a repo/0 does not compile" do
    assert_raise ArgumentError, ~r/has repo: and a repo\/0/, fn ->
      compile("""
      defmodule Sekisho.ConfigTest.TwoRepos do
        use Sekisho, repo: SekishoTest.Repo, policies: []
        def repo, do: SekishoTest.Repo
        def actor(_scope), do: nil
      end
      """)
    end
  end

  test "tables: is a short name of lowercase letters, digits and _" do
    for tables <- ["Lib", "lib-pro", "", "a_very_long_library_name", :lib] do
      assert_raise ArgumentError, ~r/tables: is the start of the names/, fn ->
        compile("""
        defmodule Sekisho.ConfigTest.BadTables do
          use Sekisho, repo: SekishoTest.Repo, policies: [], tables: #{inspect(tables)}
          def actor(_scope), do: nil
        end
        """)
      end
    end
  end

  test "a migrations module names tables of its own" do
    assert_raise ArgumentError, ~r/are Sekisho.Migrations' own/, fn ->
      compile("""
      defmodule Sekisho.ConfigTest.SameTables do
        use Sekisho.Migrations, tables: "sekisho"
      end
      """)
    end
  end

  defp compile(code), do: Code.compile_string(code)
end
