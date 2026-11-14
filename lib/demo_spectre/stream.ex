defmodule DemoSpectre.Stream do
  @moduledoc "Pull-based deterministic provider stream; the normal Server stream boundary owns previews."
  @behaviour Spectre.Inference.StreamAdapter
  alias Spectre.Inference.{ProviderEvent, Response}
  @impl true
  def capabilities(_, _), do: MapSet.new([:stream, :pull_transport])
  @impl true
  def open(descriptor, _opts) do
    with {:ok, text} <-
           DemoSpectre.Model.deterministic(Spectre.Prompt.Plan.legacy(descriptor.plan)) do
      chunks = text |> String.graphemes() |> Enum.chunk_every(12) |> Enum.map(&Enum.join/1)

      events =
        Enum.map(chunks, &ProviderEvent.delta/1) ++ [ProviderEvent.completed(Response.new(text))]

      {:ok, %{events: events, token: make_ref()}, %{}}
    end
  end

  @impl true
  def request_transport_item(%{events: [event | rest]} = state) do
    Process.send_after(self(), {__MODULE__, state.token, event}, 35)
    {:ok, %{state | events: rest}}
  end

  def request_transport_item(state), do: {:ok, state}
  @impl true
  def handle_transport({__MODULE__, token, event}, %{token: token} = state),
    do: {:ok, [event], state}

  def handle_transport(_, state), do: {:ignore, state}
  @impl true
  def cancel(_, _), do: :ok
end
