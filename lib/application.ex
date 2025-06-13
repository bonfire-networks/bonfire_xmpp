defmodule Bonfire.XMPP.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Bonfire.Common.Extend.extension_enabled?(:bonfire_xmpp),
        do: [
          # ejabberd will be started automatically as a dependency
          # We just need to start PubSub if not already started by the parent app
          # {Phoenix.PubSub, name: Bonfire.Common.PubSub},

          # Our custom ejabberd event handler
          {Bonfire.XMPP.Ejabberd.Bridge, []}
        ],
        else: []

    opts = [strategy: :one_for_one, name: Bonfire.XMPP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
