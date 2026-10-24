if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule Sekisho.LiveView do
    @moduledoc """
    Permissions in LiveView: events checked before your `handle_event/3`
    runs, and pages that lose their access while they are open.

    Add the hook to a `live_session`, after the one that sets the scope:

        live_session :app,
          on_mount: [
            {MyAppWeb.UserAuth, :require_authenticated},
            {Sekisho.LiveView, MyApp.Permissions}
          ] do
          live "/documents/:id", DocumentLive
        end

    Then, in `mount/3`, say what the page needs, and which events take
    which permission on which assign:

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

    An event of the map is refused when the scope does not have its
    permission on the assign (a flash, and your `handle_event/3` is not
    called). When access to a watched record is revoked (a grant taken
    away, a role changed, a membership of your own tables:
    `MyApp.Permissions.changed/0`), the page goes away with a flash: to
    `"/"`, or where `:revoked_to` says.

    It needs `:pubsub` in `use Sekisho`.

    ## Options

    `{Sekisho.LiveView, {MyApp.Permissions, opts}}`:

      * `:scope` — the assign of the scope (`:current_scope`).
      * `:revoked_to` — where a page goes when its access is revoked (`"/"`).
      * `:revoked` — its flash (`"You no longer have access to this page."`).
      * `:denied` — the flash of a refused event (`"You are not allowed to do that."`).

    Flashes are your words: pass translated ones (Gettext) here.
    """

    import Phoenix.LiveView

    @defaults [
      scope: :current_scope,
      revoked_to: "/",
      revoked: "You no longer have access to this page.",
      denied: "You are not allowed to do that."
    ]

    @doc false
    def on_mount(root, params, session, socket) when is_atom(root),
      do: on_mount({root, []}, params, session, socket)

    def on_mount({root, opts}, _params, _session, socket) do
      opts = Keyword.merge(@defaults, opts)
      pubsub = root.__sekisho__(:config).pubsub

      if connected?(socket) and pubsub, do: Phoenix.PubSub.subscribe(pubsub, "sekisho")

      socket =
        socket
        |> put_private(:sekisho, %{root: root, opts: opts, watched: [], events: %{}})
        |> attach_hook(:sekisho_info, :handle_info, &handle_info/2)
        |> attach_hook(:sekisho_event, :handle_event, &handle_event/3)

      {:cont, socket}
    end

    @doc "The page needs the permission on the record: when it loses it, it goes away."
    @spec watch(Phoenix.LiveView.Socket.t(), atom(), struct()) :: Phoenix.LiveView.Socket.t()
    def watch(socket, permission, record) do
      update_private(socket, fn state ->
        %{state | watched: Enum.uniq([{permission, record} | state.watched])}
      end)
    end

    @doc """
    Events checked before `handle_event/3`: `%{"delete" => {:delete,
    :document}}` takes `:delete` on `@document`.
    """
    @spec authorize_events(Phoenix.LiveView.Socket.t(), %{String.t() => {atom(), atom()}}) ::
            Phoenix.LiveView.Socket.t()
    def authorize_events(socket, events) do
      update_private(socket, fn state -> %{state | events: Map.merge(state.events, events)} end)
    end

    defp handle_info({:sekisho, _event, _info}, socket) do
      %{root: root, opts: opts, watched: watched} = state(socket)
      scope = socket.assigns[opts[:scope]]

      if Enum.all?(watched, fn {permission, record} ->
           root.allowed?(scope, permission, record)
         end) do
        {:halt, socket}
      else
        {:halt,
         socket |> put_flash(:error, opts[:revoked]) |> push_navigate(to: opts[:revoked_to])}
      end
    end

    defp handle_info(_message, socket), do: {:cont, socket}

    defp handle_event(event, _params, socket) do
      %{root: root, opts: opts, events: events} = state(socket)

      case Map.fetch(events, event) do
        {:ok, {permission, assign}} ->
          scope = socket.assigns[opts[:scope]]
          resource = Map.fetch!(socket.assigns, assign)

          if root.allowed?(scope, permission, resource),
            do: {:cont, socket},
            else: {:halt, put_flash(socket, :error, opts[:denied])}

        :error ->
          {:cont, socket}
      end
    end

    defp state(socket) do
      socket.private[:sekisho] ||
        raise ArgumentError, "Sekisho.LiveView is not in this LiveView's on_mount"
    end

    defp update_private(socket, fun), do: put_private(socket, :sekisho, fun.(state(socket)))
  end
end
