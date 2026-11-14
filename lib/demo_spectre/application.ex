defmodule DemoSpectre.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DemoSpectreWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:demo_spectre, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DemoSpectre.PubSub},
      DemoSpectre.Events,
      {Registry, keys: :unique, name: DemoSpectre.Registry},
      {DynamicSupervisor, name: DemoSpectre.Sessions, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      DemoSpectreWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DemoSpectre.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DemoSpectreWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
