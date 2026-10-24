defmodule Mix.Tasks.Sekisho.Install do
  @moduledoc """
  Installs Sekisho in a Phoenix application.

      $ mix igniter.install sekisho

  or, with Sekisho already in the deps, `mix sekisho.install`.
  [Igniter](https://hexdocs.pm/igniter) shows each change as a diff
  before it writes, and running the task again changes nothing:

    * the migration of Sekisho's tables (`mix sekisho.gen.migration`), with
      ids of your repo's type;
    * `lib/my_app/permissions.ex`, your permissions module, with no policy
      yet: your file, written once;
    * `import MyApp.Permissions, only: [allowed?: 3]` in the
      `html_helpers` of your web module, for templates;
    * `.formatter.exs` imports Sekisho's, so policies read
      `role :viewer, permissions: [:read]`.

  Then write your first policy (`Sekisho.Policy`) and add it to
  `policies:`.
  """

  use PhoenixMountable.Install,
    otp_app: :sekisho,
    migrations: Sekisho.Migrations,
    html_helpers: ["import {app}.Permissions, only: [allowed?: 3]"],
    manual: "See https://hexdocs.pm/sekisho/readme.html#install"

  if Code.ensure_loaded?(Igniter) do
    alias Igniter.Project.Formatter
    alias Igniter.Project.Module, as: Mod

    @impl PhoenixMountable.Install
    def install(igniter) do
      prefix = Mod.module_name_prefix(igniter)
      permissions = Module.concat(prefix, Permissions)

      {exists?, igniter} = Mod.module_exists(igniter, permissions)

      igniter
      |> Formatter.import_dep(:sekisho)
      |> then(fn igniter ->
        if exists?,
          do: igniter,
          else: Mod.create_module(igniter, permissions, contents(igniter, prefix))
      end)
      |> Igniter.add_notice(notice(permissions))
    end

    defp contents(igniter, prefix) do
      repo = Module.concat(prefix, Repo)
      scope = Module.concat([prefix, Accounts, Scope])
      pubsub = Module.concat(prefix, PubSub)
      {scoped?, _igniter} = Mod.module_exists(igniter, scope)

      actor =
        if scoped? do
          """
          @impl Sekisho
          def actor(%#{inspect(scope)}{user: user}), do: user
          def actor(nil), do: nil
          """
        else
          """
          # The actor your scope is: a user struct, or nil for a visitor.
          @impl Sekisho
          def actor(%{current_user: user}), do: user
          def actor(_scope), do: nil
          """
        end

      """
      @moduledoc \"\"\"
      Who may do what. See `Sekisho`.

          #{inspect(prefix)}.Permissions.allowed?(scope, :update, post)
          Post |> #{inspect(prefix)}.Permissions.where_allowed(scope, :read) |> Repo.all()
      \"\"\"
      use Sekisho,
        repo: #{inspect(repo)},
        pubsub: #{inspect(pubsub)},
        # Your policies (Sekisho.Policy), one for each schema.
        policies: []

      #{actor}
      """
    end

    defp notice(permissions) do
      """
      Sekisho: run mix ecto.migrate, then write your first policy:

          defmodule MyApp.Blog.PostPolicy do
            use Sekisho.Policy, for: MyApp.Blog.Post
            import Ecto.Query

            permissions [:read, :update]

            @impl true
            def allow(%MyApp.Accounts.User{id: id}, :update), do: dynamic([p], p.author_id == ^id)
            def allow(_user, :read), do: true
          end

      and add it to the policies: of #{inspect(permissions)}.
      """
    end
  end
end
