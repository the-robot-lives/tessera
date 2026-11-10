defmodule Mix.Tasks.Tessera.Manifest do
  @shortdoc "Aggregate tessera component manifests into tessera-manifest.json + custom-elements.json"

  @moduledoc """
  Aggregates `__tessera_manifest__/0` across every tessera component in the
  current Mix project and its loaded deps, then writes:

    * `tessera-manifest.json` — the tessera manifest (component list);
    * `custom-elements.json` — the Custom Elements Manifest
      (`Noizu.Tessera.Codegen.cem/1`, schemaVersion "1.0.0").

  Both files are written to the current project root. Run after `mix compile`
  (the scanner reads compiled beams).

      mix tessera.manifest
  """

  use Mix.Task

  alias Noizu.Tessera.{Codegen, Registry}

  @impl Mix.Task
  def run(_args) do
    modules = Registry.all_modules()

    if modules == [] do
      Mix.shell().info("tessera: no tessera components found — nothing to write")
    end

    specs = Enum.map(modules, & &1.__tessera_spec__())
    manifests = Enum.map(modules, & &1.__tessera_manifest__())

    manifest_doc = %{"contractVersion" => 1, "components" => manifests}

    File.write!("tessera-manifest.json", Jason.encode!(manifest_doc, pretty: true) <> "\n")
    File.write!("custom-elements.json", Jason.encode!(Codegen.cem(specs), pretty: true) <> "\n")

    Mix.shell().info(
      "tessera: wrote tessera-manifest.json + custom-elements.json " <>
        "(#{length(manifests)} components from #{length(Registry.tessera_apps())} apps)"
    )
  end
end
