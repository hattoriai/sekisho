defmodule SekishoTest.Scope do
  @moduledoc "The app's scope: the user, and the links a visitor followed."
  defstruct [:user, links: []]
end

defmodule SekishoTest.User do
  @moduledoc false
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :admin, :boolean, default: false
  end
end

defmodule SekishoTest.Org do
  @moduledoc false
  use Ecto.Schema

  schema "orgs" do
    field :name, :string
  end
end

defmodule SekishoTest.Membership do
  @moduledoc false
  use Ecto.Schema

  schema "memberships" do
    belongs_to :org, SekishoTest.Org
    belongs_to :user, SekishoTest.User
    field :role, :string
  end
end

defmodule SekishoTest.Team do
  @moduledoc false
  use Ecto.Schema

  schema "teams" do
    field :name, :string
  end
end

defmodule SekishoTest.TeamMembership do
  @moduledoc false
  use Ecto.Schema

  schema "team_memberships" do
    belongs_to :team, SekishoTest.Team
    belongs_to :user, SekishoTest.User
  end
end

defmodule SekishoTest.Folder do
  @moduledoc false
  use Ecto.Schema

  schema "folders" do
    field :name, :string
    belongs_to :org, SekishoTest.Org
    belongs_to :parent, SekishoTest.Folder
  end
end

defmodule SekishoTest.Project do
  @moduledoc false
  use Ecto.Schema

  schema "projects" do
    field :name, :string
  end
end

defmodule SekishoTest.Document do
  @moduledoc false
  use Ecto.Schema

  schema "documents" do
    field :title, :string
    field :locked, :boolean, default: false
    field :contract_value, :integer
    belongs_to :org, SekishoTest.Org
    belongs_to :folder, SekishoTest.Folder
    belongs_to :author, SekishoTest.User
  end
end

defmodule SekishoTest.ProjectDocument do
  @moduledoc false
  use Ecto.Schema

  schema "project_documents" do
    belongs_to :project, SekishoTest.Project
    belongs_to :document, SekishoTest.Document
  end
end

defmodule SekishoTest.Review do
  @moduledoc false
  use Ecto.Schema

  schema "reviews" do
    belongs_to :document, SekishoTest.Document
    belongs_to :reviewer, SekishoTest.User
    field :state, :string, default: "open"
  end
end

defmodule SekishoTest.Post do
  @moduledoc false
  use Ecto.Schema

  schema "posts" do
    field :title, :string
    field :published, :boolean, default: false
    field :locked, :boolean, default: false
    belongs_to :author, SekishoTest.User
  end
end
