defmodule PersonaKit.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :persona_kit,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      name: "PersonaKit",
      description:
        "tessera example component package: persona-card and persona-picker web components.",
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Fast per-change lane excludes :slow/:nightly; `mix test` runs everything.
  # See ../../docs/notes/test-tiering.md.
  defp aliases do
    [
      "test.fast": ["test --exclude slow --exclude nightly"]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # The tessera library. In the tessera repo itself this is the parent
      # checkout; when this package is consumed from elsewhere, point the path
      # at a noizu_tessera checkout (or a hex/git version once published).
      {:noizu_tessera, path: "../.."},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
