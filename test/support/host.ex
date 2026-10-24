defmodule SekishoTest.AssignScope do
  @moduledoc "The app's own on_mount: the scope, from the user in the session."
  def on_mount(:default, _params, session, socket) do
    user = session["user_id"] && SekishoTest.Repo.get(SekishoTest.User, session["user_id"])
    {:cont, Phoenix.Component.assign(socket, :current_scope, %SekishoTest.Scope{user: user})}
  end
end

defmodule SekishoTest.DocumentLive do
  @moduledoc "A page of a document, which watches :read and checks the delete event."
  use Phoenix.LiveView

  def mount(%{"id" => id}, _session, socket) do
    document = SekishoTest.Repo.get!(SekishoTest.Document, id)

    {:ok,
     socket
     |> assign(document: document, deleted: false)
     |> Sekisho.LiveView.watch(:read, document)
     |> Sekisho.LiveView.authorize_events(%{"delete" => {:delete, :document}})}
  end

  def handle_event("delete", _params, socket), do: {:noreply, assign(socket, deleted: true)}
  def handle_event("ping", _params, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <h1>{@document.title}</h1>
    <p :if={@deleted}>Deleted</p>
    <p id="flash">{Phoenix.Flash.get(@flash, :error)}</p>
    """
  end
end

defmodule SekishoTest.HomeLive do
  @moduledoc false
  use Phoenix.LiveView

  def render(assigns), do: ~H"<p id='flash'>{Phoenix.Flash.get(@flash, :error)}</p>"
end

defmodule SekishoTest.Host do
  @moduledoc "The app of the tests, with a live_session that has the hook."
  use PhoenixMountable.TestHost,
    otp_app: :sekisho,
    routes:
      (quote do
         scope "/" do
           pipe_through :browser

           live_session :app,
             on_mount: [SekishoTest.AssignScope, {Sekisho.LiveView, SekishoTest.Permissions}] do
             live "/", SekishoTest.HomeLive
             live "/documents/:id", SekishoTest.DocumentLive
           end
         end
       end)
end
