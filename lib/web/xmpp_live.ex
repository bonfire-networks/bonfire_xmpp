defmodule Bonfire.XMPP.Web.XMPPLive do
  use Bonfire.UI.Common.Web, :live_view
  import Untangle

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to ejabberd events
      Phoenix.PubSub.subscribe(Bonfire.Common.PubSub, "ejabberd:users")
      Phoenix.PubSub.subscribe(Bonfire.Common.PubSub, "ejabberd:sessions")
      
      # Refresh data periodically
      :timer.send_interval(10_000, self(), :refresh_data)
    end

    socket = 
      socket
      |> assign(:users, get_online_users())
      |> assign(:server_info, get_server_info())
      |> assign(:user_count, 0)
      |> assign(:registration_result, nil)
      |> calculate_user_count()

    {:ok, socket}
  end

  @impl true
  def handle_event("register_user", %{"username" => username, "password" => password}, socket) do
    
    result = case Bonfire.XMPP.Ejabberd.Bridge.register_user(
      username, 
      password
    ) do
      {:ok, username} -> {:success, "User #{username} registered successfully!"}
      {:error, reason} -> error(reason, l "Registration failed")
      :exists -> {:error, l "User already exists"}
      other -> error(other, l "Registration failed")
    end

    {:noreply, assign(socket, :registration_result, result)}
  end

  @impl true
  def handle_event("clear_message", _params, socket) do
    {:noreply, assign(socket, :registration_result, nil)}
  end

  @impl true
  def handle_info(:refresh_data, socket) do
    socket = 
      socket
      |> assign(:users, get_online_users())
      |> assign(:server_info, get_server_info())
      |> calculate_user_count()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:user_online, user}, socket) do
    users = get_online_users()
    
    socket = 
      socket
      |> assign(:users, users)
      |> calculate_user_count()
      |> put_flash(:info, "#{user} came online")
    
    {:noreply, socket}
  end

  @impl true
  def handle_info({:user_offline, user}, socket) do
    users = get_online_users()
    
    socket = 
      socket
      |> assign(:users, users)
      |> calculate_user_count()
      |> put_flash(:info, "#{user} went offline")
    
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <!-- Header -->
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body flex-row items-center justify-between">
          <div>
            <h1 class="card-title text-3xl">ejabberd + Phoenix LiveView</h1>
            <p class="text-base-content/70 mt-1">Real-time XMPP server</p>
          </div>
          <div class="flex items-center gap-2">
            <span class="badge badge-success badge-xs animate-pulse"></span>
            <span class="text-sm text-base-content/70">Live Updates</span>
          </div>
        </div>
      </div>

      <!-- Server Info -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h3 class="card-title text-lg mb-2">Server Status</h3>
            <div class="text-3xl font-bold text-success"><%= @server_info.status %></div>
          </div>
        </div>
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h3 class="card-title text-lg mb-2">Online Users</h3>
            <div class="text-3xl font-bold text-primary"><%= @user_count %></div>
          </div>
        </div>
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h3 class="card-title text-lg mb-2">Node</h3>
            <div class="text-sm text-base-content/70"><%= @server_info.node %></div>
          </div>
        </div>
      </div>

<%!-- 
      <!-- Instructions -->
      <div class="alert alert-info mt-6 flex flex-col items-start">
        <h3 class="font-bold mb-2">Getting Started</h3>
        <div class="space-y-2">
          <p>1. Register a user</p>
          <p>2. Connect with an XMPP client (like Gajim, Pidgin, or Conversations) to localhost:5222</p>
          <p>3. Watch the user list update in real-time as users connect/disconnect</p>
        </div>
      </div>

      <!-- User Registration -->
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body">
          <h2 class="card-title text-xl mb-4">Register New User</h2>
          <form phx-submit="register_user" class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
            <div>
              <label for="username" class="label">
                <span class="label-text">Username</span>
              </label>
              <input 
                type="text" 
                name="username" 
                id="username" 
                required
                class="input input-bordered w-full"
                placeholder="Enter username"
              />
            </div>
            <div>
              <label for="password" class="label">
                <span class="label-text">Password</span>
              </label>
              <input 
                type="password" 
                name="password" 
                id="password" 
                required
                class="input input-bordered w-full"
                placeholder="Enter password"
              />
            </div>
            <div class="md:col-span-2">
              <button 
                type="submit"
                class="btn btn-primary w-full md:w-auto"
              >
                Register User
              </button>
            </div>
          </form>

          <!-- Registration Result -->
          <div :if={@registration_result} class="mt-4">
            <div class={[
              "alert",
              if(elem(@registration_result, 0) == :success, do: "alert-success", else: "alert-error")
            ]}>
              <span><%= elem(@registration_result, 1) %></span>
              <button 
                phx-click="clear_message"
                class="btn btn-ghost btn-xs ml-auto"
              >
                ×
              </button>
            </div>
          </div>
        </div>
      </div> --%>

      <!-- Online Users -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title text-xl mb-4">
            Online Users (<%= @user_count %>)
          </h2>
          <div :if={@user_count == 0} class="text-base-content/50 italic py-8 text-center">
            No users currently online. Try registering and connecting with an XMPP client!
          </div>
          <div :if={@user_count > 0} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            <div 
              :for={user <- @users} 
              class="alert alert-success flex items-center"
            >
              <span class="badge badge-success badge-xs mr-2"></span>
              <span class="font-medium"><%= user %></span>
            </div>
          </div>
        </div>
      </div>

    </div>

    <.live_component module={Bonfire.XMPP.Web.XmppMessageFormLive} id="msgform" />
    <.live_component module={Bonfire.XMPP.Web.XmppMessageListLive} id="msglist" />
    """
  end

  defp get_online_users do
    try do
      # Get connected users from ejabberd
      :ejabberd_sm.connected_users_info()
      |> Enum.map(fn {user, server, _resource, _info} ->
        "#{user}@#{server}"
      end)
      |> Enum.uniq()
      |> Enum.sort()
    rescue
      _ -> []
    end
  end

  defp get_server_info do
    try do
      %{
        status: "Running",
        node: node(),
        version: :ejabberd_config.get_version()
      }
    rescue
      _ -> 
        %{
          status: "Unknown", 
          node: node(),
          version: "Unknown"
        }
    end
  end

  defp calculate_user_count(socket) do
    assign(socket, :user_count, length(socket.assigns.users))
  end
end