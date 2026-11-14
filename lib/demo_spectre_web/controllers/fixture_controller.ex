defmodule DemoSpectreWeb.FixtureController do
  @moduledoc "Local website visited by Lens during the deterministic showcase."
  use DemoSpectreWeb, :controller
  @doc "Serves one of two stable browser fixtures."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"page" => "studio"}) do
    html(
      conn,
      "<html><head><title>Atelier — studio Elixir</title></head><body><main><h1>Atelier</h1><p>Progettiamo applicazioni Elixir e Phoenix per piccoli team.</p><h2>Contattaci</h2><a href=\"mailto:hello@atelier.example\">hello@atelier.example</a><p>Milano, Italia. Sito dimostrativo locale.</p></main></body></html>"
    )
  end

  def show(conn, %{"page" => "no-email"}),
    do:
      html(
        conn,
        "<html><head><title>Studio senza contatto</title></head><body><main><h1>Studio senza contatto</h1><p>Questa pagina non pubblica un indirizzo email.</p></main></body></html>"
      )

  def show(conn, _), do: send_resp(conn, 404, "Not found")
end
