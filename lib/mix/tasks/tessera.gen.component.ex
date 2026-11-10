defmodule Mix.Tasks.Tessera.Gen.Component do
  @shortdoc "Scaffold a tessera component: spec module + colocated .mjs + test skeleton"

  @moduledoc """
  Scaffolds a tessera web component in the current Mix project:

      mix tessera.gen.component persona-card
      mix tessera.gen.component persona-card --module MyApp.Components.PersonaCard

  Writes:

    * the spec module (`lib/...`, from `--module`, default
      `<AppCamel>.Components.<CamelTag>`);
    * the colocated `persona_card.mjs` template (imports
      `@noizu/tessera-core`, exports `register` — replace the body, keep the
      export, CONTRACT.md §5);
    * a web-test-runner test skeleton at `test/components/persona_card_test.mjs`.

  The generated contract module (`persona_card.contract.generated.mjs`) is
  written at the next `mix compile`. Run `mix tessera.install` once per host
  app to wire `@noizu/tessera-core` into `assets/package.json`.
  """

  use Mix.Task

  alias Noizu.Tessera.Scaffold

  @switches [module: :string]

  @impl Mix.Task
  def run(args) do
    {opts, positionals, _invalid} = OptionParser.parse(args, strict: @switches)

    case positionals do
      [tag] ->
        module_name = opts[:module] || Scaffold.default_module(Mix.Project.config()[:app], tag)

        files =
          try do
            Scaffold.generate(tag, module_name, File.cwd!())
          rescue
            e in CompileError -> Mix.raise("tessera.gen.component: " <> Exception.message(e))
          end

        Enum.each(files, fn {path, content} ->
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, content)
          Mix.shell().info("tessera: created #{path}")
        end)

        Mix.shell().info(
          "tessera: run `mix compile` to generate the contract module, " <>
            "and `mix tessera.install` once per host app"
        )

      _ ->
        Mix.raise("usage: mix tessera.gen.component <tag> [--module Some.Module]")
    end
  end
end
