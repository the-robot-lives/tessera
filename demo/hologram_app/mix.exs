defmodule HologramDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :hologram_demo,
      version: "0.1.0",
      elixir: "~> 1.15",
      # Hologram's dev LiveReload watcher reads this (watched_dirs/0) —
      # omitting it crashes Hologram.LiveReload on boot.
      elixirc_paths: ["lib"],
      # The :hologram compiler bundles the client runtime + page bundles into
      # priv/static/hologram (part of `mix compile`).
      compilers: Mix.compilers() ++ [:hologram],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [mod: {HologramDemo.Application, []}, extra_applications: [:logger]]
  end

  defp deps do
    [
      # Hologram hosts its client runtime on Phoenix.
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:hologram, "~> 0.10.1"},
      # The tessera component package under examples/ — which itself path-deps
      # on the tessera library two levels up.
      {:persona_kit, path: "../../examples/persona_kit"},
      # Tier 2 spike: ordinary Hologram components compiled to standalone
      # tessera bundles (mix tessera.compile_component).
      {:holo_kit, path: "../../examples/holo_kit"}
    ]
  end
end
