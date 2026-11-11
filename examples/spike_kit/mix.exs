defmodule SpikeKit.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :spike_kit,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      name: "SpikeKit",
      description:
        "SPIKE (spike/elixir-to-lit): example components defined fully in Elixir (state + template + actions) and compiled to Lit elements.",
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # The tessera library (SPIKE branch). Consumed from elsewhere, point
      # the path at a noizu_tessera checkout on spike/elixir-to-lit.
      {:noizu_tessera, path: "../.."}
    ]
  end
end
