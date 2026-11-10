import Config

config :hologram_demo, HologramDemo.Web.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: HologramDemo.PubSub,
  # Demo-only literal: this app is a local example, never deployed. Real apps
  # take secret_key_base from runtime env.
  secret_key_base:
    "tessera-demo-local-only-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

config :logger, :default_formatter, format: "[$level] $message\n"

import_config "#{config_env()}.exs"
