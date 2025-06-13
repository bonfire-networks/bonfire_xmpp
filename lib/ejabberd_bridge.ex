defmodule Bonfire.XMPP.Ejabberd.Bridge do
  use GenServer
  import Untangle
  require Record

  @topic "xmpp:messages:web@localhost"

  # Define the record at module level
  Record.defrecord :jid, Record.extract(:jid, from: Bonfire.XMPP.jid_path())
  
  # Define the message record - we need to extract it from xmpp headers
  Record.defrecord :message, 
    id: <<>>, 
    type: :normal, 
    lang: <<>>, 
    from: :undefined, 
    to: :undefined, 
    subject: [], 
    body: [], 
    thread: :undefined, 
    sub_els: [], 
    meta: %{}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Hook into ejabberd events if possible
    # Schedule first check
    :ejabberd_hooks.add(:route, :bonfire_xmpp, &__MODULE__.on_message/4, 50)
    monitor_client_connections()
    Process.send_after(self(), :check_users, 1000)
    {:ok, %{previous_users: MapSet.new()}}
  end

  @impl true
  def handle_info(:check_users, state) do
    current_users = get_current_users()
    previous_users = state.previous_users

    # Detect new users
    new_users = MapSet.difference(current_users, previous_users)
    # Detect users who went offline
    offline_users = MapSet.difference(previous_users, current_users)

    # Broadcast changes
    Enum.each(new_users, fn user ->
      Phoenix.PubSub.broadcast(Bonfire.Common.PubSub, "ejabberd_users", {:user_online, user})
    end)

    Enum.each(offline_users, fn user ->
      Phoenix.PubSub.broadcast(Bonfire.Common.PubSub, "ejabberd_users", {:user_offline, user})
    end)

    # Schedule next check
    Process.send_after(self(), :check_users, 3000)

    {:noreply, %{state | previous_users: current_users}}
  end

  def on_message(_from, _to, _acc, stanza) do
    case stanza do
      {:xmlelement, "message", attrs, children} ->
        from = get_attr(attrs, "from") || "unknown"
        body = extract_body(children)
        Phoenix.PubSub.broadcast(Bonfire.Common.PubSub, @topic, {:xmpp_message, %{from: from, body: body}})
      _ -> :ok
    end
    :ok
  end

  defp get_attr(attrs, key), do: Enum.find_value(attrs, fn {k, v} -> if k == key, do: v end)
  defp extract_body(children) do
    Enum.find_value(children, fn
      {:xmlelement, "body", _, [{:xmlcdata, text}]} -> text
      _ -> nil
    end)
  end

  def monitor_client_connections do
    # Hook into ejabberd client events
    :ejabberd_hooks.add(:sm_register_connection_hook, :global, 
                        {__MODULE__, :on_client_connect}, 50)
    :ejabberd_hooks.add(:sm_remove_connection_hook, :global, 
                        {__MODULE__, :on_client_disconnect}, 50)
  end

  def on_client_connect(_sid, jid, _info) do
    info("Client connected: #{inspect(jid)}")
    Phoenix.PubSub.broadcast(Bonfire.Common.PubSub, "xmpp_clients", 
                            {:client_connected, jid})
    :ok
  end

  def on_client_disconnect(_sid, jid, _info) do
    info("Client disconnected: #{inspect(jid)}")
    Phoenix.PubSub.broadcast(Bonfire.Common.PubSub, "xmpp_clients", 
                            {:client_disconnected, jid})
    :ok
  end

  # User registration functions
  def register_user(username, password) when is_binary(username) and is_binary(password) do
    hostname = get_hostname()
    
    # Validate username format
    case validate_username(username) do
      :ok ->
        info("Attempting to register user: #{username}@#{hostname}")
        
        case :ejabberd_auth.try_register(username, hostname, password) do
          {:atomic, :ok} ->
            info("Successfully registered user: #{username}@#{hostname}")
            {:ok, "#{username}@#{hostname}"}
          
          {:aborted, :exists} ->
            info("User already exists: #{username}@#{hostname}")
            {:error, :user_exists}
          
          {:aborted, reason} ->
            error(reason, "Failed to register user: #{username}@#{hostname}")
            {:error, reason}
          
          :ok ->
            info("Successfully registered user: #{username}@#{hostname}")
            {:ok, "#{username}@#{hostname}"}
          
          {:error, reason} ->
            error(reason, "Failed to register user: #{username}@#{hostname}")
            {:error, reason}
          
          other ->
            error(other, "Unexpected registration result for: #{username}@#{hostname}")
            {:error, :registration_failed}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  def register_user(username, password) do
    error("Invalid username or password format: #{inspect(username)}, #{inspect(password)}")
    {:error, :invalid_input}
  end

  defp validate_username(username) when is_binary(username) do
    cond do
      String.length(username) == 0 ->
        {:error, :empty_username}
      
      String.length(username) > 64 ->
        {:error, :username_too_long}
      
      not Regex.match?(~r/^[a-zA-Z0-9._-]+$/, username) ->
        {:error, :invalid_characters}
      
      true ->
        :ok
    end
  end


  # Function to test local message sending
  def test_local_message do
    hostname = get_hostname()
    send_message("alice@#{hostname}", "bob@#{hostname}", "Hello from Alice!")
  end

  # List all registered users
  def list_users do
    hostname = get_hostname()
    try do
      :ejabberd_auth.get_users(hostname)
    rescue
      error ->
        warn("Failed to get users: #{inspect(error)}")
        []
    end
  end

  # Remove a user
  def remove_user(username) when is_binary(username) do
    hostname = get_hostname()
    
    case :ejabberd_auth.remove_user(username, hostname) do
      :ok ->
        info("Successfully removed user: #{username}@#{hostname}")
        {:ok, "User removed"}
      
      {:error, reason} ->
        error(reason, "Failed to remove user: #{username}@#{hostname}")
        {:error, reason}
      
      other ->
        error(other, "Unexpected result removing user: #{username}@#{hostname}")
        {:error, :removal_failed}
    end
  end

  defp get_current_users do
    try do
      :ejabberd_sm.connected_users()
      |> Enum.map(fn user_jid ->
        case :jid.from_string(user_jid) do
          {:error, _} -> nil
          jid_record -> 
            # Extract username from the JID record using record syntax
            user = jid(jid_record, :user)
            server = jid(jid_record, :server)
            "#{user}@#{server}"
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()
    rescue
      error ->
        warn("Failed to get current users: #{inspect(error)}")
        MapSet.new()
    end
  end

  def send_message(from, to, body) do
    # Debug the hostname configuration
    hostname = get_hostname()
    info("Current hostname config: #{hostname}")
    info("Ejabberd hosts: #{inspect(get_ejabberd_hosts())}")
    
    # Normalize both JIDs to use the correct hostname
    normalized_from = normalize_jid(from)
    normalized_to = normalize_jid(to)
    
    info("Original from: #{from}, normalized: #{normalized_from}")
    info("Original to: #{to}, normalized: #{normalized_to}")
    
    with {:ok, from_jid} <- create_jid_with_hostname(normalized_from, "from"),
         {:ok, to_jid} <- parse_jid(normalized_to, "to") do
      
      info("Created from_jid: #{inspect(from_jid)}")
      info("Created to_jid: #{inspect(to_jid)}")
      
      case validate_delivery(to_jid) do
        :local ->
          # Send to local users
          send_local_message(from_jid, to_jid, body)
        :remote ->
          # Send to remote users (may fail due to s2s issues)
          send_remote_message(from_jid, to_jid, body)
      end
    else
      {:error, reason} -> {:error, reason}
      error -> 
        error(error, "Error sending XMPP message")
    end
  end

  defp normalize_jid(jid_string) do
    hostname = get_hostname()
    info("Normalizing #{jid_string} with hostname #{hostname}")
    
    result = case String.split(jid_string, "@") do
      [user, "localhost"] -> "#{user}@#{hostname}"
      [user, server] -> "#{user}@#{server}"
      [bare_jid] -> bare_jid  # No @ symbol, return as-is
    end
    
    info("Normalization result: #{result}")
    result
  end

  defp get_hostname do
    # Try multiple ways to get the hostname
    hostname = Application.get_env(:bonfire_xmpp, :hostname) || 
               System.get_env("HOSTNAME") || 
               "localhost"
    info("Retrieved hostname: #{hostname}")
    hostname
  end

  # Create a JID ensuring it uses the correct hostname for local users
  defp create_jid_with_hostname(jid_string, field_name) do
    info("Creating JID for #{field_name}: #{jid_string}")
    
    case String.split(jid_string, "@") do
      [user, server] ->
        hostname = get_hostname()
        info("User: #{user}, Server: #{server}, Hostname: #{hostname}")
        
        # If it's trying to use localhost but we have a different hostname, use the configured one
        actual_server = if server == "localhost", do: hostname, else: server
        actual_jid_string = "#{user}@#{actual_server}"
        
        info("Creating JID from string: #{actual_jid_string}")
        
        case :jid.from_string(actual_jid_string) do
          {:error, reason} -> 
            error(reason, "Failed to parse #{field_name} for JID: #{actual_jid_string}")
          jid -> 
            info("Successfully created JID: #{inspect(jid)}")
            {:ok, jid}
        end
      _ ->
        # Fallback to regular parsing
        parse_jid(jid_string, field_name)
    end
  end

  defp validate_delivery(to_jid) do
    # Check if the destination is local or remote using record syntax
    server = jid(to_jid, :lserver)
    case :ejabberd_router.is_my_host(server) do
      true -> :local
      false -> :remote
    end
  end

  defp send_local_message(from_jid, to_jid, body) do
    with {:ok, message} <- create_message_record(from_jid, to_jid, body) do
      :ejabberd_router.route(message)
      {:ok, "Message sent to local user"}
    else
      error -> error
    end
  end

  defp send_remote_message(from_jid, to_jid, body) do
    with {:ok, message} <- create_message_record(from_jid, to_jid, body) do
      # Debug the JID before routing
      info("Routing message with from JID: #{inspect(from_jid)}")
      :ejabberd_router.route(message)
      # For remote messages, we can't guarantee delivery due to s2s issues
      {:ok, "Message queued for remote delivery (may fail due to certificate issues)"}
    else
      error -> error
    end
  end

  defp parse_jid(jid_string, field_name) do
    case :jid.from_string(jid_string) do
      {:error, reason} -> 
        error(reason, "Failed to parse #{field_name} for JID: #{jid_string}")
      jid -> {:ok, jid}
    end
  end

  defp create_message_record(from_jid, to_jid, body) do
    try do
      # Create the message using the Record macro to create a proper Erlang record
      text_elements = :xmpp.mk_text(body)
      
      message = message(
        id: generate_message_id(),
        type: :chat,
        lang: <<>>,
        from: from_jid,
        to: to_jid,
        subject: [],
        body: text_elements,
        thread: :undefined,
        sub_els: [],
        meta: %{}
      )
      
      {:ok, message}
    rescue
      error ->
        error(error, "Failed to create message record: #{inspect(error)}")
        {:error, "Failed to create message record"}
    end
  end

  defp generate_message_id do
    # Generate a simple message ID
    "msg_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  # Helper function to check if a user exists locally
  def user_exists?(jid_string) do
    normalized_jid = normalize_jid(jid_string)
    case create_jid_with_hostname(normalized_jid, "user") do
      {:ok, jid_rec} ->
        case validate_delivery(jid_rec) do
          :local -> 
            user = jid(jid_rec, :luser)
            server = jid(jid_rec, :lserver)
            :ejabberd_auth.user_exists(user, server)
          :remote -> :unknown
        end
      _ -> false
    end
  end

  # Get list of connected users with their status
  def get_connected_users do
    try do
      :ejabberd_sm.connected_users()
      |> Enum.map(fn jid_string ->
        case :jid.from_string(jid_string) do
          {:error, _} -> nil
          jid_rec -> 
            %{
              jid: jid_string,
              user: jid(jid_rec, :user),
              server: jid(jid_rec, :server),
              resource: jid(jid_rec, :resource)
            }
        end
      end)
      |> Enum.reject(&is_nil/1)
    rescue
      error ->
        warn("Failed to get connected users: #{inspect(error)}")
        []
    end
  end

  # Get the number of connected users
  def get_connected_users_count do
    try do
      :ejabberd_sm.connected_users_number()
    rescue
      error ->
        warn("Failed to get connected users count: #{inspect(error)}")
        0
    end
  end

  # Helper to check what hostname ejabberd thinks it has
  def get_ejabberd_hosts do
    try do
      :ejabberd_config.get_myhosts()
    rescue
      error ->
        warn("Failed to get ejabberd hosts: #{inspect(error)}")
        []
    end
  end

  # Testing helper functions
  @doc false
  def test_normalize_jid(jid_string) do
    normalize_jid(jid_string)
  end

  @doc false  
  def test_create_jid_with_hostname(jid_string, field_name) do
    create_jid_with_hostname(jid_string, field_name)
  end

  @doc false
  def test_validate_delivery(jid) do
    validate_delivery(jid)
  end
end