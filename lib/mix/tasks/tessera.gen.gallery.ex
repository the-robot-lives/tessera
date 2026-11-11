defmodule Mix.Tasks.Tessera.Gen.Gallery do
  @shortdoc "Scaffold the built-in interactive component gallery for a package"

  @moduledoc """
  Scaffolds the tessera component gallery for a package in the current Mix
  project:

      mix tessera.gen.gallery
      mix tessera.gen.gallery --package PersonaKit --out gallery

  Every `use Noizu.Tessera.Package` includes gallery support by default
  (it exposes `cem/0`); this task turns that into a runnable, FRAMEWORK-
  AGNOSTIC gallery — a static HTML page plus the package's own component
  bundles, no framework involved:

    * `gallery/index.html` — the static page;
    * `gallery/src/main.mjs` — esbuild entry importing the package's
      component `.mjs` modules (their load-bearing `register()` defines the
      elements) and the tessera gallery runtime (`priv/gallery/gallery.mjs`);
    * `gallery/custom-elements.json` — the package's CEM, which the runtime
      reads to render, per component: a live demo, typed attribute/property
      editors, slot-content editors, CSS custom-property editors and an
      event log (event name + camelCase detail);
    * `gallery/package.json` + `gallery/serve.mjs` — esbuild build and a
      dependency-free static server (http://localhost:5588, PORT overridable).

  Then:

      npm install        # in the PACKAGE root — esbuild resolves the
                         # components' bare imports (lit, @noizu/tessera-core)
                         # from the component files' own directory chain
      cd gallery && npm install && npm run build && npm run serve

  Re-run the task after changing the package's components to refresh the
  entry + manifest. Compiles the project first.
  """

  use Mix.Task

  alias Noizu.Tessera.{Gallery, Registry}

  @switches [package: :string, out: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _positionals, _invalid} = OptionParser.parse(args, strict: @switches)

    Mix.Task.run("compile")

    package =
      case Registry.resolve_package(opts[:package]) do
        {:ok, mod} -> mod
        {:error, message} -> Mix.raise("tessera.gen.gallery: " <> message)
      end

    tessera_root =
      cond do
        Registry.current_app() == :noizu_tessera -> File.cwd!()
        path = Mix.Project.deps_paths()[:noizu_tessera] -> path
        true -> Mix.raise("tessera.gen.gallery: cannot locate the noizu_tessera dependency")
      end

    out = opts[:out] || "gallery"

    files =
      Gallery.generate(package, File.cwd!(),
        out: out,
        tessera_root: tessera_root,
        app: Registry.current_app()
      )

    Enum.each(files, fn {path, content} ->
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      Mix.shell().info("tessera: created #{path}")
    end)

    Mix.shell().info(
      "tessera: gallery for #{inspect(package)} scaffolded in #{out}/ — " <>
        "run `cd #{out} && npm install && npm run build && npm run serve` " <>
        "(serves http://localhost:5588)"
    )
  end
end
