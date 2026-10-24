defmodule Sekisho.ModelTest do
  # What Sekisho refuses: in a policy when it compiles, and across policies
  # when the permissions module is first asked (validate!/0).
  use ExUnit.Case, async: true

  test "the test app's policies are valid" do
    assert SekishoTest.Permissions.validate!() == :ok
  end

  describe "a policy, when it compiles" do
    defp compile(body) do
      Code.compile_string("""
      defmodule SekishoTest.Bad#{System.unique_integer([:positive])} do
        use Sekisho.Policy, for: SekishoTest.Post
        #{body}
      end
      """)
    end

    test "a role gives a permission it does not declare" do
      assert_raise CompileError,
                   ~r/role :editor gives :publish, which is not in permissions/,
                   fn ->
                     compile("permissions [:read]\nrole :editor, permissions: [:publish]")
                   end
    end

    test "derive names roles that do not exist" do
      assert_raise CompileError, ~r/derive names :boss, which is not a role/, fn ->
        compile(
          "permissions [:read]\nrole :viewer, permissions: [:read]\nderive :boss, from: :viewer"
        )
      end

      assert_raise CompileError, ~r/:viewer derives from :owner, which is not a role/, fn ->
        compile(
          "permissions [:read]\nrole :viewer, permissions: [:read]\nderive :viewer, from: :owner"
        )
      end
    end

    test "grant_to takes users, groups and links" do
      assert_raise CompileError, ~r/grant_to takes :user, :group and :link, not :everyone/, fn ->
        compile("permissions [:read]\ngrant_to [:everyone]")
      end
    end
  end

  describe "the policies together" do
    defp model(policies) do
      name = Module.concat(SekishoTest, "Root#{System.unique_integer([:positive])}")

      Code.compile_string("""
      defmodule #{inspect(name)} do
        use Sekisho, repo: SekishoTest.Repo, policies: #{inspect(policies)}
        def actor(_scope), do: nil
      end
      """)

      fn -> name.validate!() end
    end

    defp policy(schema, body) do
      name = Module.concat(SekishoTest, "Policy#{System.unique_integer([:positive])}")

      Code.compile_string("""
      defmodule #{inspect(name)} do
        use Sekisho.Policy, for: #{inspect(schema)}
        #{body}
      end
      """)

      name
    end

    test "a relation the schema does not have" do
      bad =
        policy(
          SekishoTest.Folder,
          "permissions [:read]\nrole :viewer, permissions: [:read]\nderive :viewer, from: {:team, :viewer}"
        )

      assert_raise ArgumentError, ~r/SekishoTest.Folder has no belongs_to :team/, model([bad])
    end

    test "a related schema with no policy" do
      bad =
        policy(
          SekishoTest.Folder,
          "permissions [:read]\nrole :viewer, permissions: [:read]\nderive :viewer, from: {:org, :admin}"
        )

      assert_raise ArgumentError, ~r/has no policy for SekishoTest.Org/, model([bad])
    end

    test "a role the related policy does not have" do
      org = policy(SekishoTest.Org, "permissions [:read]\nrole :member, permissions: [:read]")

      bad =
        policy(
          SekishoTest.Folder,
          "permissions [:read]\nrole :viewer, permissions: [:read]\nderive :viewer, from: {:org, :admin}"
        )

      assert_raise ArgumentError,
                   ~r/derives from :admin on :org, which is not a role or a permission of/,
                   model([org, bad])
    end

    test "down a relation to the same schema, a role derives from itself" do
      bad =
        policy(SekishoTest.Folder, """
        permissions [:read, :update]
        role :viewer, permissions: [:read]
        role :editor, permissions: [:update]
        derive :viewer, from: {:parent, :editor}
        """)

      assert_raise ArgumentError, ~r/a role derives from itself/, model([bad])
    end

    test "schemas that derive from each other" do
      folder =
        policy(
          SekishoTest.Folder,
          "permissions [:read]\nrole :viewer, permissions: [:read]\nderive :viewer, from: {:org, :member}"
        )

      org =
        policy(
          SekishoTest.Org,
          "permissions [:read]\nrole :member, permissions: [:read]\nrelation :root, SekishoTest.Folder\nderive :member, from: {:root, :viewer}"
        )

      assert_raise ArgumentError, ~r/roles derive in a circle/, model([folder, org])
    end

    test "two policies for one schema" do
      a = policy(SekishoTest.Post, "permissions [:read]")
      b = policy(SekishoTest.Post, "permissions [:read]")
      assert_raise ArgumentError, ~r/two policies for one schema/, model([a, b])
    end
  end

  test "use Sekisho checks its options" do
    assert_raise ArgumentError, ~r/does not take \[:repository\]/, fn ->
      Code.compile_string("defmodule SekishoTest.BadRoot do use Sekisho, repository: X end")
    end

    assert_raise ArgumentError, ~r/needs repo:/, fn ->
      Code.compile_string("defmodule SekishoTest.BadRoot2 do use Sekisho, policies: [] end")
    end
  end
end
