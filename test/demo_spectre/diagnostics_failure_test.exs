defmodule DemoSpectre.DiagnosticsFailureTest do
  use ExUnit.Case, async: true
  alias DemoSpectre.Session

  test "a Skill that vanishes after lookup cannot crash the Session callback" do
    skill = start_supervised!({Agent, fn -> nil end})
    monitor = Process.monitor(skill)
    GenServer.stop(skill)
    assert_receive {:DOWN, ^monitor, :process, ^skill, :normal}
    root = start_supervised!({DemoSpectre.Test.DiagnosticsProbe, skill: skill})
    state = %{agent: root, owner: self()}

    assert {:reply, {:error, :diagnostic_source_unavailable}, ^state} =
             Session.handle_call(:snapshot, {self(), make_ref()}, state)
  end

  test "unavailable root diagnostic and page reads return errors without terminating Session" do
    root = start_supervised!({Agent, fn -> nil end})
    monitor = Process.monitor(root)
    GenServer.stop(root)
    assert_receive {:DOWN, ^monitor, :process, ^root, :normal}
    state = %{agent: root, owner: self()}

    for request <- [:snapshot, {:gam_page, nil}] do
      assert {:reply, {:error, :diagnostic_source_unavailable}, ^state} =
               Session.handle_call(request, {self(), make_ref()}, state)
    end
  end

  test "identical redacted records keep separate stable IDs across diagnostic pages" do
    records = List.duplicate(%{kind: :evidence, ref: nil, observed_at: 1}, 2)
    page = %{records: records, counts: %{}, revision: 1, next_cursor: :next}
    snapshot = %{gam: page, skills: %{}, root: %{version: 1}}

    source =
      start_supervised!(
        {DemoSpectre.Test.DiagnosticsProbe, snapshot: snapshot, page: %{page | next_cursor: nil}}
      )

    {:ok, socket} =
      DemoSpectreWeb.ChatLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{
        private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}}
      })

    socket = Phoenix.Component.assign(socket, :session, source)
    assert {:noreply, first} = DemoSpectreWeb.ChatLive.handle_info(:refresh, socket)
    assert {:noreply, second} = DemoSpectreWeb.ChatLive.handle_event("more_records", %{}, first)
    ids = Enum.map(second.assigns.streams.records.inserts, &elem(&1, 0))
    assert length(ids) == 4
    assert length(Enum.uniq(ids)) == 4
  end
end
