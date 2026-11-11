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
        "Write a web component once as an Elixir spec: it compiles to a custom element whose " <>
          "events arrive in your Hologram actions as plain params, with no glue code. Includes " <>
          "compile-time contract and Custom Elements Manifest codegen and the @noizu/tessera-core " <>
          "JS runtime.",
      source_url: "https://github.com/the-robot-lives/tessera",
      homepage_url: "https://tessera.noizu.com",
      deps: deps(),
      package: package(),
      docs: docs(),
      aliases: aliases()
    ]
  end

  # `mix test.fast` is an alias, so Mix does not auto-switch it to :test the
  # way the built-in `mix test` does — pin the env so it runs the test suite
  # from any caller (local runner, CI) without an explicit MIX_ENV.
  def cli do
    [preferred_envs: ["test.fast": :test]]
  end

  # Test tiering (docs/notes/test-tiering.md). The fast per-change lane runs
  # `mix test.fast`, which excludes anything tagged `:slow` or `:nightly`;
  # plain `mix test` still runs the WHOLE suite (integration + nightly lanes).
  # No current test carries those tags — the whole ExUnit suite is sub-second —
  # so the alias is the convention hook the Phase 4b conformance matrices use.
  defp aliases do
    [
      "test.fast": ["test --exclude slow --exclude nightly"]
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
    # Canary override (TESSERA_HOLOGRAM=git, see .github/workflows/canary.yml):
    # compile against noizu-forks/hologram branch `dev` instead of the hex pin
    # so upstream Hologram drift surfaces in the scheduled canary. PR CI never
    # sets the flag and keeps the pin (mix.lock unchanged).
    hologram_dep =
      if System.get_env("TESSERA_HOLOGRAM") == "git" do
        {:hologram, github: "noizu-forks/hologram", branch: "dev", runtime: false, optional: true}
      else
        # Isomorphic UI. `runtime: false` — a component library, not a Hologram
        # app. In a release (no Mix), Hologram.Reflection.otp_app/0 takes THE one
        # loaded application whose .app `applications` lists :hologram and
        # badmatches when there are two (the host crash-looped at boot with
        # `{badmatch, [:tobor_kit_hologram, host]}` — see tobor-kit hologram
        # mix.exs). Keeping :hologram out of this library's `applications` leaves
        # the host as the only candidate. The code dependency is unchanged (our
        # adapter compiles against Hologram.Component); the host depends on
        # :hologram itself, which puts it in the release and starts it.
        {:hologram, "~> 0.10.0", runtime: false, optional: true}
      end

    [
      hologram_dep,
      # Unrestricted on purpose — contract/manifest codegen and tsr-props
      # encoding use Jason at compile and render time, including in :prod.
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "noizu_tessera",
      licenses: ["MIT"],
      maintainers: ["Noizu Labs"],
      links: %{
        "GitHub" => "https://github.com/the-robot-lives/tessera",
        "Website" => "https://tessera.noizu.com",
        "Changelog" => "https://github.com/the-robot-lives/tessera/blob/main/CHANGELOG.md"
      },
      files: ~w(lib priv mix.exs README.md CHANGELOG.md docs LICENSE),
      # priv/js ships the @noizu/tessera-core npm package dir; node_modules is
      # a local install artifact and must never enter the hex tarball. `dist`
      # is likewise a build artifact — the npm package's entry points all
      # resolve to src/*.mjs, so it is never needed at runtime.
      exclude_patterns: ["node_modules", "dist", "*.contract.generated.mjs"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md" | Path.wildcard("docs/*.md")],
      groups_for_extras: [
        Guides: ~w(docs/AUTHORING.md docs/CONSUMING.md docs/EXTENDING.md),
        Reference: ~w(docs/CONTRACT.md)
      ],
      groups_for_docs: []
    ]
  end
end
