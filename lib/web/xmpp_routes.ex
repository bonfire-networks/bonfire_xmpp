defmodule Bonfire.XMPP.Web.Routes do
  @behaviour Bonfire.UI.Common.RoutesModule

  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/xmpp", Bonfire.XMPP.Web do
        pipe_through(:browser)

        
      end

      # pages you need to view as a user
      scope "/xmpp", Bonfire.XMPP.Web do
        pipe_through(:browser)
        pipe_through(:user_required)
        
            live "/", XMPPLive, :index
      end

      # pages you need an account to view
      scope "/xmpp", Bonfire.XMPP.Web do
        pipe_through(:browser)
        pipe_through(:account_required)


      end
    end
  end
end
