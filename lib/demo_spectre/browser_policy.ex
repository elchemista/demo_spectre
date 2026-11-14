defmodule DemoSpectre.BrowserPolicy do
  @moduledoc "Restricts the deterministic showcase to its local fixture URLs."
  @doc "Authorizes only fixture navigation; existing tab reads keep their policy."
  @spec authorize(atom(), map(), keyword()) :: :ok | {:error, atom()}
  def authorize(operation, args, _opts) when operation in [:open, :look] do
    case Map.get(args, "url") || Map.get(args, :url) do
      nil ->
        :ok

      url ->
        uri = URI.parse(url)

        if uri.host == "127.0.0.1" and uri.path in ["/fixtures/studio", "/fixtures/no-email"] and
             uri.port == DemoSpectreWeb.Endpoint.config(:http)[:port] and uri.scheme == "http" and
             is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment),
           do: :ok,
           else: {:error, :use_local_fixture_url}
    end
  end

  def authorize(_, _, _), do: {:error, :operation_not_enabled}
end
