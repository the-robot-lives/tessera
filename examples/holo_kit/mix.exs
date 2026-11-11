defmodule HoloKit.MixProject do
  use Mix.Project

  def project do
    [
      app: :holo_kit,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # Tier 2 spike package: components are ORDINARY Hologram components,
      # compiled by Hologram's own compiler via `mix tessera.compile_component`.
      {:hologram, "~> 0.10.1"},
      # The tessera library (provides the compile task + the JS shim sources).
      {:noizu_tessera, path: "../../"}
    ]
  end
end
