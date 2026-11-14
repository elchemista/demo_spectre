defmodule DemoSpectre.Session do
  @moduledoc """
  Relays the authenticated local UI to one Agent and its mounted Skill Servers.

  Configures identity, storage and allowed operations once at root startup.
  Spectre owns the automatic GAM connection, Domain, ledger and execution path;
  the children reuse them while keeping local state, checkpoints and pending
  intentions. Session is a UI/resource owner, not a GAM implementation.
  """
  use GenServer, restart: :temporary, shutdown: 40_000
  alias Spectre.Server

  @doc "Starts a monitored browser session."
  @spec start(pid()) :: {:ok, pid()} | {:error, term()}
  def start(owner), do: DynamicSupervisor.start_child(DemoSpectre.Sessions, {__MODULE__, owner})
  @doc false
  @spec start_link(pid()) :: GenServer.on_start()
  def start_link(owner), do: GenServer.start_link(__MODULE__, owner)
  @doc "Returns public references for the UI, without an authority handle."
  @spec info(pid()) :: map()
  def info(session), do: GenServer.call(session, :info)
  @doc "Returns runtime state and the authoritative GAM projection."
  @spec snapshot(pid()) :: map()
  def snapshot(session), do: GenServer.call(session, :snapshot)
  @doc "Submits actual user input through this session's authenticated UI owner."
  @spec input(pid(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def input(session, text, opts \\ []),
    do: GenServer.call(session, {:input, text, opts}, :infinity)

  @doc "Acknowledges rendering; this does not approve an action."
  @spec presented(pid(), String.t()) :: :ok | {:error, term()}
  def presented(session, ref), do: GenServer.call(session, {:presented, ref})
  @doc "Submits the UI owner's decision for one exact presentation."
  @spec decide(pid(), atom(), String.t(), :confirm | :reject) :: {:ok, term()} | {:error, term()}
  def decide(session, skill, ref, decision),
    do: GenServer.call(session, {:decide, skill, ref, decision}, :infinity)

  @impl true
  def init(owner) do
    Process.flag(:trap_exit, true)
    id = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    monitor = Process.monitor(owner)
    stack_name = {:via, Registry, {DemoSpectre.Registry, {:stack, id}}}

    {:ok, stack} =
      Spectre.Stack.Runtime.start_link(DemoSpectre.AI,
        name: stack_name,
        packages: [
          lens: [network_policy: :any],
          mnemonic: [
            storage_id: "demo-session:" <> id,
            data_root: Path.join(Application.fetch_env!(:demo_spectre, :data_root), "memory"),
            namespace: "demo"
          ]
        ]
      )

    path = Path.join(Application.fetch_env!(:demo_spectre, :data_root), id <> ".ledger")
    {:ok, store} = Spectre.Ledger.ServerStore.start_link(path: path)
    domain = "demo:" <> id

    {:ok, agent} =
      Server.start_link(
        agent: DemoSpectre.Agent,
        consumer: self(),
        identity: %{subject: id, conversation: id},
        stack_runtime: stack_name,
        namespace: "demo",
        ledger_server_store: store,
        checkpoint: {Spectre.Ledger.ServerStore, store, :agent},
        gam: [
          # Spectre builds GAM for the identity bound to this UI session.
          # This demo uses a random session identity instead of an account login.
          # Both Skill Servers receive this same connection; no per-Skill Domain.
          domain: domain,
          # Authority history and coordination checkpoints have matching durability.
          storage:
            {:disk, Path.join(Application.fetch_env!(:demo_spectre, :data_root), id <> ".gam")},
          store: {Spectre.Ledger.ServerStore, store},
          operations: operations()
        ],
        max_steps: 80
      )

    {:ok,
     %{
       id: id,
       domain: domain,
       owner: owner,
       monitor: monitor,
       store: store,
       stack: stack,
       agent: agent
     }}
  end

  @impl true
  def handle_call(:info, _, state),
    do: {:reply, Map.take(state, [:id, :agent, :domain]), state}

  def handle_call(:snapshot, _, state) do
    skills =
      Map.new([:outreach, :knowledge], fn skill ->
        value =
          case Server.skill_server(state.agent, skill) do
            {:ok, pid} -> Map.put(Server.status(pid), :pid, inspect(pid))
            {:error, reason} -> %{pending: [], error: reason}
          end

        {skill, value}
      end)

    result =
      case Server.gam_view(state.agent) do
        {:ok, view} -> %{skills: skills, gam: view, root: Server.status(state.agent)}
        {:error, _} = error -> error
      end

    {:reply, result, state}
  end

  def handle_call({:presented, ref}, {owner, _}, %{owner: owner} = state),
    do: {:reply, Server.presented(state.agent, ref), state}

  def handle_call({:decide, skill, ref, decision}, {owner, _}, %{owner: owner} = state),
    do: {:reply, Server.decide(state.agent, skill, ref, decision), state}

  def handle_call({:input, text, opts}, {owner, _}, %{owner: owner} = state),
    do: {:reply, Server.input(state.agent, text, opts), state}

  def handle_call(_, _, state), do: {:reply, {:error, :unauthorized_transport}, state}

  @impl true
  def handle_info({Spectre.Server.GAM.Managed, _, {:presentation, show}}, state) do
    send(state.owner, {:presentation, show})
    {:noreply, state}
  end

  def handle_info({Server, agent, event}, %{agent: agent} = state) do
    send(state.owner, {:agent_event, event})
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _, _}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info({:EXIT, pid, reason}, state) do
    if pid in [state.agent, state.store, state.stack],
      do: {:stop, {:session_component_stopped, reason}, state},
      else: {:noreply, state}
  end

  @impl true
  def terminate(_, state) do
    Enum.each([state.agent, state.store, state.stack], &stop/1)
    DemoSpectre.Events.forget(state.id)
    :ok
  end

  @spec operations() :: map()
  defp operations do
    %{
      {{:skill, :outreach}, :kinetic, :send_email} => [
        confirm: true,
        class: "demo.email",
        message: "Inviare l’email nella casella locale?"
      ],
      {{:skill, :knowledge}, :kinetic, :log_hello} => [
        confirm: true,
        class: "demo.log",
        message: "Scrivere hello nel log dell’applicazione?"
      ],
      save_report: [
        confirm: true,
        class: "demo.memory",
        message: "Salvare nella memoria della sessione?"
      ],
      forget_memory: [confirm: true, class: "demo.forget", message: "Dimenticare questo ricordo?"],
      learn_memory: [
        confirm: true,
        class: "demo.learn",
        message: "Salvare questa conoscenza riutilizzabile?"
      ],
      send_notice: [
        confirm: true,
        class: "demo.beam",
        message: "Inviare una notifica nella casella locale?"
      ]
    }
  end

  @spec stop(pid()) :: :ok
  defp stop(pid) do
    GenServer.stop(pid, :normal, 35_000)
  catch
    :exit, _ -> :ok
  end
end
