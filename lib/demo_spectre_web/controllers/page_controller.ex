defmodule DemoSpectreWeb.PageController do
  use DemoSpectreWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
