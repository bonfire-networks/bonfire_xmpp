defmodule Bonfire.XMPP.Web.XmppMessageFormLive do
  use Phoenix.LiveComponent
  import Untangle

  @impl true
  def mount(socket) do
    {:ok, assign(socket, to: "", body: "", sending: false, feedback: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow mb-6">
      <div class="card-body">
        <h2 class="card-title">Send XMPP Message</h2>
        <form phx-submit="send_xmpp_msg" phx-target={@myself} class="space-y-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text">To (user@domain)</span>
            </label>
            <input
              type="text"
              name="to"
              placeholder="recipient@example.com"
              value={@to}
              class="input input-bordered w-full"
              required
            />
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Message</span>
            </label>
            <textarea
              name="body"
              placeholder="Type your message here..."
              value={@body}
              class="textarea textarea-bordered w-full"
              rows="3"
              required
            />
          </div>

          <div class="form-control">
            <button
              type="submit"
              class={[
                "btn btn-primary",
                if(@sending, do: "loading", else: "")
              ]}
              disabled={@sending}
            >
              <%= if @sending, do: "Sending...", else: "Send Message" %>
            </button>
          </div>
        </form>

        <div :if={@feedback} class="mt-4">
          <div class={[
            "alert",
            if(String.starts_with?(@feedback, "Error"), do: "alert-error", else: "alert-success")
          ]}>
            <span><%= @feedback %></span>
            <button
              phx-click="clear_feedback"
              phx-target={@myself}
              class="btn btn-ghost btn-xs ml-auto"
            >
              ×
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("send_xmpp_msg", %{"to" => to, "body" => body}, socket) do
    socket = assign(socket, sending: true, feedback: nil)

    # Validate recipient format
    case String.split(to, "@") do
      [_user, _domain] ->
        # Or get from current user session
        from = "web@localhost"

        case Bonfire.XMPP.Ejabberd.Bridge.send_message(from, to, body) do
          {:ok, message} ->
            {:noreply, assign(socket, sending: false, feedback: message, to: "", body: "")}

          {:error, reason} ->
            {:noreply, assign(socket, sending: false, feedback: "Error: #{reason}")}
        end

      _ ->
        {:noreply,
         assign(socket,
           sending: false,
           feedback: "Error: Invalid recipient format. Use user@domain"
         )}
    end
  end

  @impl true
  def handle_event("clear_feedback", _params, socket) do
    {:noreply, assign(socket, feedback: nil)}
  end
end
