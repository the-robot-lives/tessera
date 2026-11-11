defmodule HologramDemo.Web.Endpoint do
  @moduledoc """
  Demo endpoint: static Hologram bundles, the standard request pipeline
  (Parsers for command POST bodies, session for the Hologram session id +
  csrf token), then the Hologram page router.
  """

  use Phoenix.Endpoint, otp_app: :hologram_demo

  # Serves the Hologram client runtime + page bundles that the :hologram
  # compiler writes into priv/static/hologram, and the standalone tessera
  # bundles written by `mix tessera.compile_component` (Tier 2 spike) into
  # priv/static/tessera.
  plug Plug.Static,
    at: "/",
    from: :hologram_demo,
    only: ~w(hologram tessera),
    gzip: false

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  plug Plug.Session,
    store: :cookie,
    key: "_hologram_demo",
    signing_salt: "tessera-demo"

  plug :fetch_session

  # Hologram pages + commands BEFORE the (empty) Phoenix router.
  plug Hologram.Router
  plug HologramDemo.Web.Router
end
