defmodule Bonfire.XMPP.Web.XmppMessageListLive do
  use Phoenix.LiveComponent

  # Use "xmpp:messages:#{current_user_jid}" in real usage
  @topic "xmpp:messages:web@localhost"

  @impl true
  def mount(socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Bonfire.Common.PubSub, @topic)
    {:ok, assign(socket, messages: [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ul class="divide-y divide-gray-200">
      <%= for msg <- @messages do %>
        <li>
          <span class="font-bold"><%= msg.from %>:</span>
          <span><%= msg.body %></span>
        </li>
      <% end %>
    </ul>
    """
  end

  @impl true
  def handle_info({:xmpp_message, msg}, socket) do
    {:noreply, update(socket, :messages, &[msg | &1])}
  end
end
