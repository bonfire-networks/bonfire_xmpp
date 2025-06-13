defmodule Bonfire.XMPP.Ejabberd.BridgeTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias Bonfire.XMPP.Ejabberd.Bridge

  setup_all do
    # Ensure ejabberd is running
    case GenServer.whereis(Bridge) do
      nil ->
        {:ok, _pid} = Bridge.start_link([])

      _pid ->
        :ok
    end

    # Get the configured hostname
    hostname = Bridge.get_hostname()

    # Clean up any existing test users
    cleanup_test_users(hostname)

    %{hostname: hostname}
  end

  setup %{hostname: hostname} do
    # Clean up before each test
    cleanup_test_users(hostname)
    :ok
  end

  describe "hostname configuration" do
    test "retrieves hostname from environment", %{hostname: hostname} do
      assert is_binary(hostname)
      assert String.length(hostname) > 0
      refute hostname == ""
    end

    test "ejabberd recognizes the configured hostname", %{hostname: hostname} do
      hosts = Bridge.get_ejabberd_hosts()
      assert is_list(hosts)
      assert hostname in hosts
    end
  end

  describe "JID normalization" do
    test "normalizes localhost to configured hostname", %{hostname: hostname} do
      # Test the normalize_jid function (we need to make it public for testing)
      # For now, we'll test through the send_message flow
      result =
        capture_log(fn ->
          Bridge.send_message("test@localhost", "user@example.com", "test message")
        end)

      assert result =~ "web@#{hostname}"
      assert result =~ "Normalizing test@localhost"
      assert result =~ "normalized: test@#{hostname}"
    end

    test "preserves non-localhost domains", %{hostname: _hostname} do
      result =
        capture_log(fn ->
          Bridge.send_message("user@example.com", "test@localhost", "test message")
        end)

      assert result =~ "user@example.com"
      assert result =~ "Normalizing user@example.com"
      assert result =~ "normalized: user@example.com"
    end
  end

  describe "user management" do
    test "creates test users successfully", %{hostname: hostname} do
      log =
        capture_log(fn ->
          Bridge.create_test_users()
        end)

      assert log =~ "alice@#{hostname} created"
      assert log =~ "bob@#{hostname} created"

      # Verify users exist
      users = Bridge.list_users()
      user_names = Enum.map(users, fn {user, _server} -> user end)
      assert "alice" in user_names
      assert "bob" in user_names
    end

    test "lists users correctly", %{hostname: hostname} do
      # Create test users first
      Bridge.create_test_users()

      users = Bridge.list_users()
      assert is_list(users)

      # Should have at least alice and bob
      user_names = Enum.map(users, fn {user, _server} -> user end)
      assert "alice" in user_names
      assert "bob" in user_names
    end

    test "user_exists? works for local users", %{hostname: hostname} do
      # Create test users first
      Bridge.create_test_users()

      assert Bridge.user_exists?("alice@#{hostname}") == true
      assert Bridge.user_exists?("bob@#{hostname}") == true
      assert Bridge.user_exists?("nonexistent@#{hostname}") == false
    end

    test "user_exists? returns :unknown for remote users" do
      assert Bridge.user_exists?("user@external.com") == :unknown
    end
  end

  describe "JID creation and validation" do
    test "creates valid JIDs with correct hostname", %{hostname: hostname} do
      log =
        capture_log(fn ->
          Bridge.send_message("alice@localhost", "bob@localhost", "test")
        end)

      # Check that JIDs are created with the correct hostname
      assert log =~ "Successfully created JID"
      assert log =~ hostname
      # Should not contain localhost in final JID
      refute log =~ "localhost"
    end
  end

  describe "message sending" do
    test "sends message between local users successfully", %{hostname: hostname} do
      # Create test users
      Bridge.create_test_users()

      {result, log} =
        with_log(fn ->
          Bridge.send_message("alice@#{hostname}", "bob@#{hostname}", "Hello Bob!")
        end)

      assert {:ok, message} = result
      assert message == "Message sent to local user"

      # Verify the message was processed correctly
      assert log =~ "Creating JID from string: alice@#{hostname}"
      assert log =~ "Creating JID from string: bob@#{hostname}"
      assert log =~ "Successfully created JID"
    end

    test "attempts to send message to remote users", %{hostname: hostname} do
      {result, log} =
        with_log(fn ->
          Bridge.send_message("alice@#{hostname}", "user@external.com", "Hello remote!")
        end)

      assert {:ok, message} = result
      assert message =~ "remote delivery"

      # Should attempt s2s connection
      assert log =~ "Routing message with from JID"
      assert log =~ hostname
    end

    test "handles invalid JIDs gracefully" do
      {result, _log} =
        with_log(fn ->
          Bridge.send_message("invalid-jid", "also-invalid", "test")
        end)

      assert {:error, _reason} = result
    end

    test "test_local_message helper works", %{hostname: hostname} do
      # Create test users
      Bridge.create_test_users()

      {result, log} =
        with_log(fn ->
          Bridge.test_local_message()
        end)

      assert {:ok, _message} = result
      assert log =~ "alice@#{hostname}"
      assert log =~ "bob@#{hostname}"
      assert log =~ "Hello from Alice!"
    end
  end

  describe "connected users monitoring" do
    test "gets connected users count" do
      count = Bridge.get_connected_users_count()
      assert is_integer(count)
      assert count >= 0
    end

    test "gets connected users list" do
      users = Bridge.get_connected_users()
      assert is_list(users)

      # Each user should have required fields
      Enum.each(users, fn user ->
        assert Map.has_key?(user, :jid)
        assert Map.has_key?(user, :user)
        assert Map.has_key?(user, :server)
        assert Map.has_key?(user, :resource)
      end)
    end
  end

  describe "delivery validation" do
    test "correctly identifies local vs remote users", %{hostname: hostname} do
      # Create test users
      Bridge.create_test_users()

      # Test local user
      {_result, log} =
        with_log(fn ->
          Bridge.send_message("alice@#{hostname}", "bob@#{hostname}", "local test")
        end)

      assert log =~ "Message sent to local user"

      # Test remote user
      {_result, log} =
        with_log(fn ->
          Bridge.send_message("alice@#{hostname}", "user@remote.com", "remote test")
        end)

      assert log =~ "remote delivery"
    end
  end

  # Helper functions
  defp cleanup_test_users(hostname) do
    # Try to remove test users if they exist
    try do
      :ejabberd_auth.remove_user("alice", hostname)
      :ejabberd_auth.remove_user("bob", hostname)
    rescue
      # Ignore errors if users don't exist
      _ -> :ok
    end
  end

  defp with_log(fun) do
    log = capture_log(fun)
    result = fun.()
    {result, log}
  end
end
