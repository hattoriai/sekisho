defmodule Sekisho.SQL.Dialect.MySQL do
  @moduledoc "MySQL and MariaDB: an indexed binary column has a length (a varbinary)."
  use Sekisho.SQL.Dialect

  @impl true
  def column(:token_hash), do: {:varbinary, size: 32}
end
