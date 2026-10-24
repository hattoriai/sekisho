defmodule Mix.Tasks.Sekisho.InstallTest do
  # Igniter applies the test project's config to the application environment
  # while it runs: not async.
  use ExUnit.Case, async: false

  import Igniter.Test

  @web """
  defmodule TestWeb do
    def html do
      quote do
        use Phoenix.Component
        unquote(html_helpers())
      end
    end

    defp html_helpers do
      quote do
        import Phoenix.HTML
        alias Phoenix.LiveView.JS
      end
    end
  end
  """

  @scope """
  defmodule Test.Accounts.Scope do
    defstruct user: nil
  end
  """

  @repo """
  defmodule Test.Repo do
    use Ecto.Repo, otp_app: :test, adapter: Ecto.Adapters.Postgres
  end
  """

  defp install(files \\ %{}) do
    [
      app_name: :test,
      files:
        Map.merge(
          %{
            ".formatter.exs" =>
              "[import_deps: [:phoenix], inputs: [\"{lib,test}/**/*.{ex,exs}\"]]\n",
            "lib/test_web.ex" => @web,
            "lib/test/repo.ex" => @repo
          },
          files
        )
    ]
    |> test_project()
    |> Igniter.compose_task(Mix.Tasks.Sekisho.Install, [])
  end

  defp file(igniter, path) do
    igniter
    |> apply_igniter!()
    |> Map.fetch!(:rewrite)
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  test "writes the permissions module, on the app's scope" do
    permissions =
      install(%{"lib/test/accounts/scope.ex" => @scope}) |> file("lib/test/permissions.ex")

    assert permissions =~ "use Sekisho"
    assert permissions =~ "repo: Test.Repo"
    assert permissions =~ "pubsub: Test.PubSub"
    assert permissions =~ "policies: []"
    assert permissions =~ "def actor(%Test.Accounts.Scope{user: user}), do: user"
  end

  test "without phx.gen.auth's scope, an actor to write" do
    permissions = install() |> file("lib/test/permissions.ex")
    assert permissions =~ "def actor(%{current_user: user}), do: user"
  end

  test "imports allowed?/3 for templates, and Sekisho's formatter" do
    igniter = install()

    assert file(igniter, "lib/test_web.ex") =~ "import Test.Permissions, only: [allowed?: 3]"

    formatter =
      igniter.rewrite |> Rewrite.source!(".formatter.exs") |> Rewrite.Source.get(:content)

    assert formatter =~ ":sekisho"
  end

  test "writes the migration of Sekisho's tables" do
    igniter = install() |> apply_igniter!()

    assert Enum.any?(
             Rewrite.paths(igniter.rewrite),
             &(&1 =~ ~r/priv\/repo\/migrations\/\d+_add_sekisho/)
           )
  end

  test "leaves the app's own permissions module, and changes nothing the second time" do
    install()
    |> apply_igniter!()
    |> Igniter.compose_task(Mix.Tasks.Sekisho.Install, [])
    |> assert_unchanged()
  end
end
