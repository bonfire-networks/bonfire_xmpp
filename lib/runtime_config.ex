defmodule Bonfire.XMPP.RuntimeConfig do
  use Bonfire.Common.Localise

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  @doc """
  Sets runtime configuration for the extension (typically by reading ENV variables).
  """
  def config do
    import Config

    yes? = ~w(true yes 1)
    no? = ~w(false no 0)

    with_xmpp = System.get_env("WITH_XMPP")

    config :bonfire_xmpp,
      modularity: (with_xmpp && with_xmpp not in no?) || :disabled

    release_path = System.get_env("RELEASE_ROOT")

    conf_root =
      release_path ||
        case System.get_env("RELIVE", "false") do
          "true" -> "_build/relive"
          "false" -> Path.expand("../", __DIR__)
        end

    # Get hostname from environment variable, fallback to localhost
    hostname = System.get_env("HOSTNAME") || "localhost"

    # Check if we're in development mode
    is_dev = Mix.env() == :dev || System.get_env("MIX_ENV") == "dev"

    # Generate ejabberd config file with environment variable substitution
    ejabberd_config_path = substitute_ejabberd_config(conf_root, hostname, is_dev)

    config :ejabberd,
      file: ejabberd_config_path,
      log_path:
        System.get_env("EJABBERD_LOG") ||
          Path.join(release_path || "", "data/xmpp/logs/ejabberd.log")

    config :mnesia,
      dir: Path.join(release_path || "", "data/xmpp/db")

    config :exsync,
      reload_callback: {:ejabberd_admin, :update, []}

    # Store hostname for use in XMPP module
    config :bonfire_xmpp,
      hostname: hostname,
      dev_mode: is_dev
  end

  defp substitute_ejabberd_config(conf_root, hostname, is_dev) do
    template_path = Path.join([conf_root, "config", "ejabberd.yml"])
    generated_path = Path.join([conf_root, "config", "ejabberd_runtime.yml"])

    case File.read(template_path) do
      {:ok, content} ->
        # Substitute environment variables
        updated_content =
          content
          |> String.replace("@HOSTNAME@", hostname)
          # Replace any remaining localhost references
          |> String.replace("localhost", hostname)
          |> modify_for_dev_if_needed(is_dev)

        # Ensure the directory exists
        Path.dirname(generated_path) |> File.mkdir_p!()

        # Write the updated config
        File.write!(generated_path, updated_content)
        generated_path

      {:error, _} ->
        # Fallback to original if template doesn't exist
        template_path
    end
  end

  defp modify_for_dev_if_needed(content, true) do
    # In dev mode, allow STARTTLS but don't verify certificates
    content
    |> String.replace(~r/s2s_use_starttls:\s*\w+/, "s2s_use_starttls: optional")
    |> ensure_dev_options()
  end

  defp modify_for_dev_if_needed(content, false), do: content

  defp ensure_dev_options(content) do
    dev_s2s_config = """

    # Development S2S options - allow STARTTLS but skip certificate verification
    s2s_protocol_options:
      - "verify: verify_none"
      - "fail_if_no_peer_cert: false"
    """

    # Only add if not already present
    if String.contains?(content, "s2s_protocol_options:") do
      content
    else
      content <> dev_s2s_config
    end
  end
end
