# The tests run against PostgreSQL at DATABASE_URL, as CI does:
#
#     DATABASE_URL=postgres://postgres:postgres@localhost/sekisho_test mix test
url = System.get_env("DATABASE_URL") || "postgres://postgres:postgres@localhost/sekisho_test"

Application.put_env(:sekisho, SekishoTest.Repo,
  url: url,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  log: false
)

_ = Ecto.Adapters.Postgres.storage_down(Ecto.Repo.Supervisor.parse_url(url))
:ok = Ecto.Adapters.Postgres.storage_up(Ecto.Repo.Supervisor.parse_url(url))
{:ok, _pid} = SekishoTest.Repo.start_link()
{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: SekishoTest.PubSub)

defmodule SekishoTest.Migration do
  use Ecto.Migration

  def up do
    Sekisho.Migrations.up(version: 1)

    create table(:users) do
      add :name, :text
      add :admin, :boolean, default: false
    end

    create table(:orgs), do: add(:name, :text)

    create table(:memberships) do
      add :org_id, references(:orgs)
      add :user_id, references(:users)
      add :role, :text
    end

    create table(:teams), do: add(:name, :text)

    create table(:team_memberships) do
      add :team_id, references(:teams)
      add :user_id, references(:users)
    end

    create table(:folders) do
      add :name, :text
      add :org_id, references(:orgs)
      add :parent_id, references(:folders)
    end

    create table(:projects), do: add(:name, :text)

    create table(:documents) do
      add :title, :text
      add :locked, :boolean, default: false
      add :contract_value, :integer
      add :org_id, references(:orgs)
      add :folder_id, references(:folders)
      add :author_id, references(:users)
    end

    create table(:project_documents) do
      add :project_id, references(:projects)
      add :document_id, references(:documents)
    end

    create table(:reviews) do
      add :document_id, references(:documents)
      add :reviewer_id, references(:users)
      add :state, :text, default: "open"
    end

    create table(:posts) do
      add :title, :text
      add :published, :boolean, default: false
      add :locked, :boolean, default: false
      add :author_id, references(:users)
    end
  end
end

Ecto.Migrator.up(SekishoTest.Repo, 1, SekishoTest.Migration, log: false)

ExUnit.start()
