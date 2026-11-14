defmodule DemoSpectre.MailActions do
  @moduledoc "Kinetic action catalog. The admitted host executor records this local receipt."
  use SpectreKinetic
  require Logger
  @al ~s(SEND EMAIL TO="hello@atelier.example" BODY="Hello from Spectre")
  @doc "Prepare the local mailbox receipt; no SMTP or external delivery is configured."
  @spec send_email(String.t(), String.t()) :: {:ok, map()}
  def send_email(to, body), do: {:ok, %{to: to, body: body, transport: "local mailbox"}}

  @al ~s(LOG HELLO MESSAGE="hello")
  @doc "Writes the requested hello only when the admitted host executor invokes the action."
  @spec log_hello(String.t()) :: {:ok, map()}
  def log_hello(message) when message == "hello" do
    Logger.info("[demo.kinetic] hello")
    {:ok, %{message: "hello", destination: "Logger"}}
  end
end
