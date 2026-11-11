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
      # The tessera component packages under examples/ — which themselves
      # path-dep on the tessera library two levels up.
      {:persona_kit, path: "../../examples/persona_kit"},
      # SPIKE (spike/elixir-to-lit): the element-DSL package — state/template/
      # action compiled into generated Lit elements (docs/notes/spike-elixir-to-lit.md).
      {:spike_kit, path: "../../examples/spike_kit"}
    ]
  end
end
