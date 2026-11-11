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
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Tier-2 serving bundles. The /holo_runtime glue (holo_runtime_glue.js)
  # dynamic-imports /tessera/tessera-runtime.esm.js + the four component
  # bundles, served by the endpoint's Plug.Static from priv/static/tessera.
  # `mix tessera.install` only wires assets/npm — it does NOT emit these
  # bundles; without this step every page whose bundle carries the glue
  # 404s on the runtime (the e2e-smoke RED bug). CI + scripts/acceptance.sh
  # run `mix tessera.bundles` BEFORE booting the demo.
  defp aliases do
    [
      "tessera.bundles":
        "tessera.compile_component HoloKit.Components.EditableList HoloKit.Components.Counter HoloKit.Components.StateProbe HoloKit.Components.PipelineProbe HoloKit.Components.SlotProbe HoloKit.Components.FormProbe ThirdParty.FancyList ThirdParty.TidyList --out priv/static/tessera"
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
      {:spike_kit, path: "../../examples/spike_kit"},
      # Tier 2 spike: ordinary Hologram components compiled to standalone
      # tessera bundles (mix tessera.compile_component).
      {:holo_kit, path: "../../examples/holo_kit"}
    ]
  end
end
