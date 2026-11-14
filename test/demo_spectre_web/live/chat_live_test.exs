defmodule DemoSpectreWeb.ChatLiveTest do
  use DemoSpectreWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "chat renders two skills and all nine packages, root answers input", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#chat-form")
    assert has_element?(view, "#target-outreach")
    assert has_element?(view, "#target-knowledge")
    assert has_element?(view, "#tool-lens")
    assert has_element?(view, "#tool-lab")
    view |> form("#chat-form", chat: %{text: "status"}) |> render_submit()

    await(fn ->
      has_element?(view, "#messages .from-agent .message-body", "Agente disponibile")
    end)

    view |> element("#run-diagnostics") |> render_click()
    await(fn -> has_element?(view, "#tool-lab.used") end)
    assert has_element?(view, "#messages .from-knowledge")
  end

  test "a consent appears only after the presentation hook ack and can be rejected", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    view |> element("#save-note") |> render_click()
    await(fn -> has_element?(view, "[phx-hook=Presentation]") end)
    html = render(view) |> LazyHTML.from_fragment()
    [ref] = html |> LazyHTML.query("[phx-hook=Presentation]") |> LazyHTML.attribute("data-ref")
    render_hook(view, "presented", %{"ref" => ref})
    await(fn -> has_element?(view, "#pending-requests [data-status=foreground]") end)
    view |> element("#pending-requests button[phx-value-answer=annulla]") |> render_click()

    await(fn ->
      has_element?(view, "#messages .from-knowledge .message-body", "Richiesta chiusa")
    end)

    refute has_element?(view, "#mailbox article")
  end

  test "malformed client events preserve the session", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    session = :sys.get_state(view.pid).socket.assigns.session

    for {event, payload} <- [
          {"target", %{"target" => "missing"}},
          {"tab", %{"tab" => "missing"}},
          {"unknown", %{}},
          {"send", %{"chat" => %{"text" => []}}},
          {"send", %{}},
          {"confirm",
           %{"skill" => "knowledge", "id" => "x", "revision" => 1, "answer" => "confermo"}}
        ] do
      render_hook(view, event, payload)
      assert :sys.get_state(view.pid).socket.assigns.session == session
    end

    view |> element("#agent-status") |> render_click()
    await(fn -> has_element?(view, "#messages .from-agent", "Agente disponibile") end)
  end

  test "GAM diagnostics load bounded pages and reset when the revision changes", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")

    for index <- 1..8 do
      view
      |> form("#chat-form", chat: %{text: "ricorda Segreto diagnostico #{index}."})
      |> render_submit()

      await(fn -> count(view, "[phx-hook=Presentation]") == index end)
      html = render(view) |> LazyHTML.from_fragment()

      ref =
        html
        |> LazyHTML.query("[phx-hook=Presentation]")
        |> LazyHTML.attribute("data-ref")
        |> List.last()

      render_hook(view, "presented", %{"ref" => ref})
      await(fn -> has_element?(view, "#pending-requests [data-status=foreground]") end)
      view |> element("#pending-requests button[phx-value-answer=annulla]") |> render_click()
      await(fn -> not has_element?(view, "#pending-requests [data-status=foreground]") end)
    end

    view |> element("#tab-gam") |> render_click()
    await(fn -> has_element?(view, "#more-gam-records") end)
    assert count(view, "#gam-records details") == 50
    refute has_element?(view, "#gam-records", "Segreto diagnostico")
    view |> element("#more-gam-records") |> render_click()
    await(fn -> count(view, "#gam-records details") > 50 end)

    view |> element("#save-note") |> render_click()
    await(fn -> count(view, "[phx-hook=Presentation]") == 9 end)
    await(fn -> count(view, "#gam-records details") == 50 end)
  end

  test "session shutdown leaves a stable disconnected page even if a refresh is queued", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")
    session = :sys.get_state(view.pid).socket.assigns.session
    GenServer.stop(session)
    await(fn -> has_element?(view, "#session-error") end)
    send(view.pid, :refresh)
    assert has_element?(view, "#send-message[disabled]")
    render_hook(view, "send", %{"chat" => %{"text" => "confermo"}})
    assert has_element?(view, "#session-error")
  end

  test "a diagnostic timeout preserves the live chat and last snapshot until retry", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    await(fn -> :sys.get_state(view.pid).socket.assigns.operational != %{} end)
    before = :sys.get_state(view.pid).socket.assigns
    :ok = :sys.suspend(before.agent)

    try do
      send(view.pid, :refresh)
      await(fn -> has_element?(view, "#diagnostic-warning") end, 250)
      current = :sys.get_state(view.pid).socket.assigns
      assert current.session == before.session
      assert current.agent == before.agent
      assert current.operational == before.operational
      refute has_element?(view, "#session-error")
      refute has_element?(view, "#send-message[disabled]")
    after
      :sys.resume(before.agent)
    end

    view |> element("#retry-diagnostics") |> render_click()
    await(fn -> not has_element?(view, "#diagnostic-warning") end)
    view |> element("#agent-status") |> render_click()
    await(fn -> has_element?(view, "#messages .from-agent", "Agente disponibile") end)
  end

  test "terminal preview events finalize only their own stream", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    send(view.pid, {:agent_event, {:skill, :outreach, {:preview, "one", "g1", "Prima"}}})
    send(view.pid, {:agent_event, {:skill, :knowledge, {:preview, "two", "g2", "Se"}}})
    send(view.pid, {:agent_event, {:skill, :outreach, {:preview_end, "one", "g1", :completed}}})
    send(view.pid, {:agent_event, {:skill, :knowledge, {:preview, "two", "g2", "conda"}}})
    assert has_element?(view, "#messages-preview-outreach-one-g1[data-preview-status=completed]")
    assert has_element?(view, "#messages-preview-knowledge-two-g2 .message-body", "Seconda")

    send(
      view.pid,
      {:agent_event, {:skill, :knowledge, {:preview_end, "two", "g2", {:error, :disconnected}}}}
    )

    assert has_element?(
             view,
             "#messages-preview-knowledge-two-g2[data-preview-status=interrupted]"
           )
  end

  defp await(fun, attempts \\ 150)
  defp await(fun, 0), do: assert(fun.())

  defp await(fun, attempts) do
    if fun.() do
      :ok
    else
      receive do
      after
        30 -> await(fun, attempts - 1)
      end
    end
  end

  defp count(view, selector),
    do: view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
end
