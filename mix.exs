defmodule NoizuTessera.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :noizu_tessera,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Noizu.Tessera",
      description:
        "Shippable web components with Hologram hooks — spec DSL, codegen and the Hologram adapter.",
      source_url: "https://github.com/the-robot-lives/tessera",
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :jason]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Isomorphic UI. `runtime: false` — a component library, not a Hologram
      # app. In a release (no Mix), Hologram.Reflection.otp_app/0 takes THE one
      # loaded application whose .app `applications` lists :hologram and
      # badmatches when there are two (the host crash-looped at boot with
      # `{badmatch, [:tobor_kit_hologram, host]}` — see tobor-kit hologram
      # mix.exs). Keeping :hologram out of this library's `applications` leaves
      # the host as the only candidate. The code dependency is unchanged (our
      # adapter compiles against Hologram.Component); the host depends on
      # :hologram itself, which puts it in the release and starts it.
      {:hologram, "~> 0.10.0", runtime: false, optional: true},
      # Unrestricted on purpose — contract/manifest codegen and tsr-props
      # encoding use Jason at compile and render time, including in :prod.
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "noizu_tessera",
      files: ~w(lib priv mix.exs README.md CHANGELOG.md docs),
      # priv/js ships the @noizu/tessera-core npm package dir; node_modules is
      # a local install artifact and must never enter the hex tarball.
      exclude_patterns: ["node_modules", "*.contract.generated.mjs"]
    ]
  end

  defp docs do
    [
      main: "Noizu.Tessera",
      source_ref: "v#{@version}",
      groups_for_docs: []
    ]
  end
end
