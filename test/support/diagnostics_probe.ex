defmodule DemoSpectre.Test.DiagnosticsProbe do
  @moduledoc false
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  @impl true
  def init(opts), do: {:ok, opts}
  @impl true
  def handle_call({Spectre.Server.Runtime, :skill_server, _}, _, opts),
    do: {:reply, {:ok, Keyword.fetch!(opts, :skill)}, opts}

  def handle_call({Spectre.Server.Runtime, :diagnostics, :operational, _}, _, opts),
    do: {:reply, {:ok, %{version: 1}}, opts}

  def handle_call(:snapshot, _, opts), do: {:reply, Keyword.fetch!(opts, :snapshot), opts}
  def handle_call({:gam_page, _}, _, opts), do: {:reply, {:ok, Keyword.fetch!(opts, :page)}, opts}
end
