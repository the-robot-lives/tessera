defmodule Mix.Tasks.Tessera.Golden do
  @shortdoc "Regenerate the reviewed test goldens (contract module + CEM)"

  @moduledoc """
  Rewrites the checked-in goldens under `test/fixtures/` from the CURRENT
  generators:

    * `persona_card.contract.golden.mjs` — the generated JS contract module
      (CONTRACT.md §2), the wire interface every consumer compiles against;
    * `persona_card.cem.json` — the Custom Elements Manifest golden.

  The ExUnit suite compares generator output against these files byte-for-byte
  and FAILS when they are missing or stale — it never bootstraps them (a
  self-bootstrapping golden can never fail, which is exactly why the old
  contract golden was vacuous on fresh checkouts).

  Regeneration is therefore an explicit, reviewed step. After an INTENTIONAL
  generator change:

      MIX_ENV=test mix tessera.golden

  then review the diff by eye against CONTRACT.md §2 before committing — the
  contract module is the wire interface, and a silent codegen change breaks
  every consumer. (MIX_ENV=test compiles `test/support`, where the
  PersonaCard fixture spec lives.)

  Run with `--check` to only verify the goldens are current (CI-style, no
  write).
  """

  use Mix.Task

  alias Noizu.Tessera.Codegen

  # The fixture spec lives in test/support (test env only), so this module
  # compiles in :dev with the fixture undefined — suppress the static-call
  # warning and rely on the runtime guard below for a friendly error.
  @compile {:no_warn_undefined, Tessera.TestFixtures.PersonaCard}

  @switches [check: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, _positionals, _invalid} = OptionParser.parse(args, strict: @switches)

    Mix.Task.run("compile")

    unless Code.ensure_loaded?(Tessera.TestFixtures.PersonaCard) do
      Mix.raise(
        "tessera.golden: the PersonaCard fixture spec is not compiled — " <>
          "it lives in test/support, which only compiles under MIX_ENV=test. " <>
          "Run: MIX_ENV=test mix tessera.golden"
      )
    end

    spec = Tessera.TestFixtures.PersonaCard.__tessera_spec__()
    dir = Path.expand("test/fixtures", File.cwd!())
    contract_path = Path.join(dir, "persona_card.contract.golden.mjs")
    cem_path = Path.join(dir, "persona_card.cem.json")

    contract = Codegen.contract_module(spec)
    cem = Jason.encode!(Codegen.cem([spec]), pretty: true) <> "\n"

    if opts[:check] do
      check_golden(contract_path, contract, "contract module")
      check_golden(cem_path, cem, "CEM")
    else
      File.write!(contract_path, contract)
      File.write!(cem_path, cem)

      Mix.shell().info("tessera: regenerated #{contract_path}")
      Mix.shell().info("tessera: regenerated #{cem_path}")

      Mix.shell().info(
        "tessera: REVIEW the diff against CONTRACT.md §2 before committing — " <>
          "the contract module is the wire interface for every consumer."
      )
    end
  end

  defp check_golden(path, expected, what) do
    actual = File.read!(path)

    if actual == expected do
      Mix.shell().info("tessera: #{what} golden is current (#{path})")
    else
      Mix.raise(
        "tessera.golden: #{what} golden is STALE (#{path}) — " <>
          "run `MIX_ENV=test mix tessera.golden` and review the diff"
      )
    end
  end
end
