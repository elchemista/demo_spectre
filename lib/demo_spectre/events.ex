defmodule DemoSpectre.Events do
  @moduledoc "Bounded local demo observations; not the GAM authority ledger."
  use GenServer
  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  @impl true
  def init(state), do: {:ok, state}
  @doc "Returns the private PubSub topic for a local session."
  @spec topic(String.t()) :: String.t()
  def topic(id), do: "demo:" <> id

  @doc "Appends and broadcasts a bounded application observation."
  @spec publish(String.t(), atom(), map()) :: map()
  def publish(id, kind, data) do
    GenServer.call(__MODULE__, {:publish, id, kind, data})
  end

  @doc "Reads up to 200 session observations; these are not the authority ledger."
  @spec history(String.t()) :: [map()]
  def history(id), do: GenServer.call(__MODULE__, {:history, id})

  @doc "Drops the disposable UI trace; this does not dispose GAM Duties."
  @spec forget(String.t()) :: :ok
  def forget(id), do: GenServer.cast(__MODULE__, {:forget, id})

  @doc "Projects a successful recorded outcome into the local demo receipt panel."
  @spec record_result(String.t(), atom(), term()) :: :ok
  def record_result(
        id,
        tag,
        {:governed, %{act: act, evidence: evidence, outcome: %{status: :succeeded}}}
      ) do
    classes = %{
      sent: "demo.email",
      saved: "demo.memory",
      forgotten: "demo.forget",
      learned: "demo.learn",
      hello_logged: "demo.log",
      notified: "demo.beam"
    }

    if class = classes[tag] do
      receipt = Enum.find_value(evidence, %{}, & &1.payload)

      publish(id, :effect, %{
        class: class,
        ref: act.ref,
        result: receipt,
        payload: act.consequence
      })
    end

    :ok
  end

  def record_result(_id, _tag, _result), do: :ok

  @impl true
  def handle_cast({:forget, id}, state), do: {:noreply, Map.delete(state, id)}

  @impl true
  def handle_call({:history, id}, _from, state), do: {:reply, Map.get(state, id, []), state}

  def handle_call({:publish, id, kind, data}, _from, state) do
    event = %{
      id: Integer.to_string(System.unique_integer([:positive, :monotonic])),
      kind: kind,
      data: data,
      time: DateTime.utc_now() |> Calendar.strftime("%H:%M:%S UTC")
    }

    Phoenix.PubSub.broadcast(DemoSpectre.PubSub, topic(id), {:demo_event, event})
    {:reply, event, Map.update(state, id, [event], &Enum.take(&1 ++ [event], -200))}
  end
end
