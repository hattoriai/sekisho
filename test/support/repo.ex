defmodule SekishoTest.Repo do
  @moduledoc "The repo of the tests, on PostgreSQL (DATABASE_URL)."
  use Ecto.Repo, otp_app: :sekisho, adapter: Ecto.Adapters.Postgres
end
