defmodule Mix.Tasks.Tessera.Cem do
  @shortdoc "Write a package's Custom Elements Manifest (custom-elements.json)"

  @moduledoc """
  Writes the Custom Elements Manifest (`Noizu.Tessera.Codegen.cem/1`,
  schemaVersion "1.0.0") for a tessera component package:

      mix tessera.cem
      mix tessera.cem --package PersonaKit
      mix tessera.cem --output priv/static/custom-elements.json

  With no `--package`, aggregates every package declared in the CURRENT
  project (`use Noizu.Tessera.Package`); `--package Module` scopes to one.
  This is the package-scoped sibling of `mix tessera.manifest` (which
  aggregates across all loaded apps and also writes tessera-manifest.json)
  — both derive from the same `__tessera_spec__/0` / `Codegen.cem/1`
  infrastructure, never a parallel registry.

  The manifest is what the built-in gallery reads (`mix tessera.gen.gallery`).
  Compiles the project first, so it is safe to run on a fresh checkout.
  """

  use Mix.Task

  alias Noizu.Tessera.{Codegen, Registry}

  @switches [package: :string, output: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _positionals, _invalid} = OptionParser.parse(args, strict: @switches)

    Mix.Task.run("compile")

    packages =
      case opts[:package] do
        nil ->
          case Registry.package_modules(Registry.current_app()) do
            [] ->
              Mix.raise(
                "tessera.cem: no tessera package found in the current project — " <>
                  "declare one with `use Noizu.Tessera.Package, components: [...]`"
              )

            mods ->
              mods
          end

        name ->
          case Registry.resolve_package(name) do
            {:ok, mod} -> [mod]
            {:error, message} -> Mix.raise("tessera.cem: " <> message)
          end
      end

    specs =
      Enum.flat_map(packages, fn package ->
        Enum.map(package.components(), & &1.__tessera_spec__())
      end)

    output = opts[:output] || "custom-elements.json"
    File.mkdir_p!(Path.dirname(output))
    File.write!(output, Jason.encode!(Codegen.cem(specs), pretty: true) <> "\n")

    Mix.shell().info(
      "tessera: wrote #{output} (#{length(specs)} components from " <>
        "#{Enum.map_join(packages, ", ", &inspect/1)})"
    )
  end
end
