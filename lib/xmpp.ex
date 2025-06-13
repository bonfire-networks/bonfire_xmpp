defmodule Bonfire.XMPP do
    @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  use Bonfire.Common.Config
  use Bonfire.Common.Localise
  alias Bonfire.Common.Utils
  import Untangle
  import Bonfire.Common.Modularity.DeclareHelpers

  declare_extension(
    "Bonfire.XMPP",
    icon: "bi:app",
    description: l("An awesome extension")
    # default_nav: [
    #   Bonfire.XMPP.Web.HomeLive
    # ]
  )


  def repo, do: Config.repo()

  def project_path, do: Config.get(:project_path) || File.cwd!()
  def jid_path, do: Path.join(project_path(), "deps/xmpp/include/jid.hrl")


  # Send a message using ejabberd_router
  defdelegate send_message(from, to, body), to: Bonfire.XMPP.Ejabberd.Bridge



end