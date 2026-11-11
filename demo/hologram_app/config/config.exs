import Config

config :hologram_demo, HologramDemo.Web.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: HologramDemo.PubSub,
  # Demo-only: this app is a local example, never deployed. secret_key_base
  # comes from the runtime env when set; the fallback is an obviously-fake
  # DEMO-ONLY filler (right shape, no entropy) so secret scanners stop
  # flagging fresh commits. Real deployments always set SECRET_KEY_BASE.
  secret_key_base:
    System.get_env("SECRET_KEY_BASE") ||
      "tessera-demo-local-only-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

config :logger, :default_formatter, format: "[$level] $message\n"

import_config "#{config_env()}.exs"
