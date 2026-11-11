defmodule HologramDemo.Application do
  @moduledoc """
  Minimal OTP app for the tessera Hologram demo — PubSub + endpoint, no
  database, no repo.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: HologramDemo.PubSub},
      HologramDemo.Web.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: HologramDemo.Supervisor)
  end
end
