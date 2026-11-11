defmodule Mix.Tasks.Tessera.CompileComponent do
  @shortdoc "Compiles Hologram components into standalone tessera bundles (Tier 2 spike)"

  @moduledoc """
  Compiles one or more ORDINARY Hologram components into standalone,
  host-agnostic bundles using Hologram's own compiler (Tier 2 spike).

      mix tessera.compile_component HoloKit.Components.EditableList \\
                                     HoloKit.Components.Counter \\
                                     ThirdParty.FancyList

  Options:

  * `--out <dir>` — output dir (default: `priv/static/tessera-holo`)

  Third-party extension modules (spike item A) are picked up from
  `test/support/third_party/**/*.ex` under the current project, compiled
  to a scratch ebin and put on the code path before the Hologram pipeline
  runs — so `use <BaseComponent>, tag: "..."` derived components compile
  alongside the originals.

  Requires a Hologram app context (run from the host app whose deps
  include both `:hologram` and `:noizu_tessera`).
  """

  use Mix.Task

  alias Noizu.Tessera.Hologram.Standalone

  @recursive false

  @impl Mix.Task
  def run(args) do
    {opts, modules, _invalid} = OptionParser.parse(args, strict: [out: :string])

    if modules == [] do
      Mix.raise("tessera.compile_component expects at least one component module name")
    end

    unless Code.ensure_loaded?(Hologram.Compiler) do
      Mix.raise("tessera.compile_component must run inside an app with :hologram as a dep")
    end

    compile_third_party!()

    Standalone.compile(modules, opts)
  end

  defp compile_third_party! do
    dir = Path.join(File.cwd!(), "test/support/third_party")

    sources =
      if File.dir?(dir) do
        Path.wildcard(Path.join(dir, "**/*.ex"))
      else
        []
      end

    if sources == [] do
      Mix.shell().info("[tessera-holo] no third-party components in #{dir}")
      []
    else
      ebin_dir = Path.join(File.cwd!(), "_build/tessera_holo_third_party")
      File.mkdir_p!(ebin_dir)

      Mix.shell().info("[tessera-holo] compiling third-party components: #{inspect(sources)}")

      case Kernel.ParallelCompiler.compile(sources, beam_dest: ebin_dir) do
        {:ok, _modules, _warnings} ->
          Code.append_path(ebin_dir)
          sources

        {:error, errors} ->
          formatted =
            Enum.map_join(errors, "\n", fn {file, line, msg} -> "  #{file}:#{line}: #{msg}" end)

          Mix.raise("third-party component compilation failed:\n#{formatted}")
      end
    end
  end
end
