# Phoenix

Sekisho's questions take your scope and return plain values, so they work
the same in a context, a controller, a JSON API, a LiveView or an Oban
job. This guide shows each.

## In your contexts

Ask in the context, where the data is loaded, so every caller gets the
same answer:

```elixir
def get_document!(scope, id) do
  document = Repo.get!(Document, id)
  :ok = Permissions.authorize!(scope, :read, document)
  document
end

def update_document(scope, document, attrs) do
  with :ok <- Permissions.authorize(scope, :update, document) do
    document |> Document.changeset(attrs) |> Repo.update()
  end
end

def list_documents(scope) do
  Document |> Permissions.where_allowed(scope, :read) |> Repo.all()
end
```

## Controllers

`authorize!/3` raises `Sekisho.Denied`, whose `plug_status` is 403.
Phoenix renders it with your error views, as it renders a 404:

```elixir
def edit(conn, %{"id" => id}) do
  document = Docs.get_document!(conn.assigns.current_scope, id)
  :ok = Permissions.authorize!(conn.assigns.current_scope, :update, document)
  render(conn, :edit, document: document)
end
```

To answer 404 instead, so that no one learns a record exists, set
`deny_as: :not_found` in `use Sekisho`. GitHub does this for private
repositories.

## Templates

The installer imports `allowed?/3` in your `html_helpers`:

```heex
<.link :if={allowed?(@current_scope, :update, @document)} navigate={~p"/documents/#{@document}/edit"}>
  Edit
</.link>
```

For a table, ask once for every row with `with_permissions/3`:

```elixir
rows = Permissions.with_permissions(documents, scope, [:update, :delete])
```

```heex
<tr :for={{document, can} <- @rows}>
  <td>{document.title}</td>
  <td><.link :if={:update in can} navigate={~p"/documents/#{document}/edit"}>Edit</.link></td>
  <td><.button :if={:delete in can} phx-click="delete" phx-value-id={document.id}>Delete</.button></td>
</tr>
```

## JSON

The same calls, and `redact/2` for the fields a person may not see:

```elixir
def show(conn, %{"id" => id}) do
  scope = conn.assigns.current_scope
  employee = HR.get_employee!(scope, id)
  render(conn, :show, employee: Permissions.redact(scope, employee))
end
```

A `Sekisho.Denied` raised in a JSON controller renders your `ErrorJSON`
for 403.

## LiveView

Add the hook to the `live_session`, after the one that sets the scope:

```elixir
live_session :app,
  on_mount: [
    {MyAppWeb.UserAuth, :require_authenticated},
    {Sekisho.LiveView, MyApp.Permissions}
  ] do
  live "/documents/:id", DocumentLive
end
```

In `mount/3`, say what the page needs, and which events take which
permission on which assign:

```elixir
def mount(%{"id" => id}, _session, socket) do
  document = Docs.get_document!(socket.assigns.current_scope, id)

  {:ok,
   socket
   |> assign(document: document)
   |> Sekisho.LiveView.watch(:read, document)
   |> Sekisho.LiveView.authorize_events(%{
     "save" => {:update, :document},
     "delete" => {:delete, :document}
   })}
end
```

* **Events.** A LiveView is authorized when it mounts, and then takes
  events for as long as it is open. An event of the map is checked
  before your `handle_event/3`: when the scope does not have the
  permission on the assign, it is refused with a flash, and your code is
  not called.
* **Revoked access.** When access to a watched record is taken away while
  the page is open (a grant revoked, a role changed, a membership of your
  own tables after `Permissions.changed/0`), the page goes away, with a
  flash, within moments, on every node of your cluster.

Both need `pubsub:` in `use Sekisho`. The options of the hook set the
flashes (your words, translated) and where a revoked page goes:

```elixir
{Sekisho.LiveView,
 {MyApp.Permissions,
  revoked_to: "/documents",
  revoked: gettext("This document is no longer shared with you."),
  denied: gettext("You cannot do that here.")}}
```

## Oban jobs and scripts

There is no request, so build the scope the job acts as:

```elixir
def perform(%Oban.Job{args: %{"user_id" => user_id, "document_id" => id}}) do
  scope = Scope.for_user(Accounts.get_user!(user_id))
  document = Repo.get!(Document, id)

  with :ok <- Permissions.authorize(scope, :update, document) do
    Docs.reindex(document)
  end
end
```

Check again in the job: access can change between the click and the run.

## GraphQL

Each field that returns a list resolves through `where_allowed/3`, so the
records a person may not see are never loaded, and pages count right.
For the fields of each object, use `redact/2` in the resolver, or
`allowed_fields/2` in a middleware.
