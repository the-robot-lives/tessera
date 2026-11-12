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

    warn_unsatisfied_pins(specs)

    Mix.shell().info(
      "tessera: wrote tessera-manifest.json + custom-elements.json " <>
        "(#{length(manifests)} components from #{length(Registry.tessera_apps())} apps)"
    )
  end

  # §8.4: unsatisfied pins surface as WARNINGS here — hard failure is the
  # host's policy choice. The Elixir lane already fails fast at derivation
  # (Extension.check_pin!/3 raises CompileError on MAJOR); this pass catches
  # drift an already-compiled derived module can still ship: its declared
  # extension_api disagrees with its base's on the MAJOR axis (e.g. the base
  # was bumped without recompiling the extender, or a pin requirement string
  # outlives the major it was satisfied by).
  defp warn_unsatisfied_pins(specs) do
    by_module = Map.new(specs, &{&1.module, &1})

    for %Noizu.Tessera.Spec{derived_from: base} = spec <- specs,
        not is_nil(base),
        base_spec = by_module[base],
        not is_nil(base_spec) do
      api = spec.extension_api || Noizu.Tessera.Spec.default_extension_api()
      base_api = base_spec.extension_api || Noizu.Tessera.Spec.default_extension_api()

      if pin_unsatisfied?(spec.extension_api_pin, api, base_api) do
        Mix.shell().warn(
          "tessera: #{spec.tag} declares extension_api #{inspect(api)} but its base " <>
            "#{inspect(base)} declares #{inspect(base_api)} — pin unsatisfied at manifest " <>
            "time (§8.4); recompile or re-pin `use #{inspect(base)}, extension_api: …`. " <>
            "Warning only — failing here is host policy."
        )
      end
    end

    :ok
  end

  # §8.4 (owner decision 2026-11-12): a pinned module stores its requirement
  # string, so the check is a real Version.match? against the base's CURRENT
  # version — a vendor minor bump inside "~> 1.0" stays quiet, a major bump
  # warns. Unpinned modules (or an unparsable base version) fall back to the
  # MAJOR comparison of the inherited version.
  @doc false
  def pin_unsatisfied?(pin, api, base_api) when is_binary(pin) do
    # Same caret normalisation as Extension.check_pin!/3: "^1.2.0" ⇒ "~> 1.2".
    requirement =
      case pin do
        "^" <> rest ->
          case String.split(rest, ".") do
            [major, minor | _] -> "~> #{major}.#{minor}"
            _ -> pin
          end

        _ ->
          pin
      end

    with {:ok, version} <- Version.parse(base_api),
         {:ok, req} <- Version.parse_requirement(requirement) do
      not Version.match?(version, req)
    else
      _ -> major(api) != major(base_api)
    end
  end

  def pin_unsatisfied?(_pin, api, base_api), do: major(api) != major(base_api)

  defp major(value) do
    case Regex.run(~r/\d+/, to_string(value)) do
      [digits] -> String.to_integer(digits)
      _ -> 0
    end
  end
end
