import Config

config :hologram_demo, HologramDemo.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 5586],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  server: true

config :phoenix, :plug_init_mode, :runtime
