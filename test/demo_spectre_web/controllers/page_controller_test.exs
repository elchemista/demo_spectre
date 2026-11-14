defmodule DemoSpectreWeb.PageControllerTest do
  use DemoSpectreWeb.ConnCase

  test "GET / renders the showcase", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Spectre"
  end
end
