defmodule DemoSpectreWeb.Router do
  use DemoSpectreWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DemoSpectreWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DemoSpectreWeb do
    pipe_through :browser

    live_session :demo do
      live "/", ChatLive, :index
    end

    get "/fixtures/:page", FixtureController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", DemoSpectreWeb do
  #   pipe_through :api
  # end
end
