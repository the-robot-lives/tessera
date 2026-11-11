defmodule Mix.Tasks.Tessera.FromLit do
  @shortdoc "Convert a Lit component into a tessera component stub (extract shape + scaffold)"

  @moduledoc """
  Converts an existing Lit 3 component (`.js`/`.ts`) into a tessera component
  stub in the current Mix project:

      mix tessera.from_lit assets/js/persona-widget.ts
      mix tessera.from_lit src/my-element.ts --out packages/my_element
      mix tessera.from_lit src/my-element.ts --module MyApp.Components.MyElement --tag my-element

  Runs `Noizu.Tessera.FromLit.Extractor` (mechanical shape extraction:
  reactive properties, events, slots, styles) and then
  `Noizu.Tessera.FromLit.Generator`, writing the same file set as
  `mix tessera.gen.component`:

    * the spec module (`lib/...`, attr/prop/event/slot/cy DSL from the shape);
    * the colocated `<snake_tag>.mjs` Lit element stub (extracted styles
      carried over, `register` export kept — CONTRACT.md §5);
    * a web-test-runner test skeleton at `test/components/<snake_tag>_test.mjs`.

  The output is a STUB, not a transpiled element: everything the contract
  grammar cannot represent is reported as a warning (also embedded in the
  generated moduledoc). Existing files are never overwritten unless `--force`.

  Options:

    * `--out <dir>` — project root to write into (default: cwd);
    * `--module Some.Module` — spec module name (default
      `<AppCamel>.Components.<CamelTag>`);
    * `--tag my-tag` — override the tag when the source has no
      `@customElement`/`customElements.define` (otherwise derived from the
      filename, with a warning);
    * `--force` — overwrite existing files.

  Run `mix compile` afterwards to generate the contract module, and
  `mix tessera.install` once per host app. See `docs/notes/from-lit.md`.
  """

  use Mix.Task

  alias Noizu.Tessera.FromLit.Extractor
  alias Noizu.Tessera.FromLit.Generator
  alias Noizu.Tessera.Scaffold

  @switches [out: :string, module: :string, tag: :string, force: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, positionals, _invalid} = OptionParser.parse(args, strict: @switches)

    case positionals do
      [path] ->
        convert(path, opts)

      _ ->
        Mix.raise(
          "usage: mix tessera.from_lit <path> [--out <dir>] [--module Some.Module] [--tag my-tag] [--force]"
        )
    end
  end

  defp convert(path, opts) do
    shape =
      case Extractor.extract_file(path) do
        {:ok, shape} ->
          shape

        {:error, reason} ->
          Mix.raise("tessera.from_lit: cannot read #{path}: #{:file.format_error(reason)}")
      end

    {tag, tag_warnings} = resolve_tag(shape, path, opts[:tag])
    shape = Map.put(shape, "tag", tag)

    module_name = opts[:module] || Scaffold.default_module(Mix.Project.config()[:app], tag)
    root = Path.expand(opts[:out] || File.cwd!())

    {files, gen_warnings} =
      try do
        Generator.generate(shape, module_name, root)
      rescue
        e in CompileError -> Mix.raise("tessera.from_lit: " <> Exception.message(e))
      end

    print_shape(shape, tag_warnings ++ gen_warnings)

    Enum.each(files, fn {file_path, content} ->
      if File.exists?(file_path) and not opts[:force] do
        Mix.shell().info("tessera: exists, skipped #{file_path} (use --force to overwrite)")
      else
        File.mkdir_p!(Path.dirname(file_path))
        File.write!(file_path, content)
        Mix.shell().info("tessera: created #{file_path}")
      end
    end)

    Mix.shell().info(
      "tessera: STUB generated — verify the contract against the original element, " <>
        "then run `mix compile` (contract module) and `mix tessera.install` once per host app"
    )
  end

  defp resolve_tag(_shape, _path, tag) when is_binary(tag), do: {tag, []}

  defp resolve_tag(%{"tag" => tag}, _path, _opts) when is_binary(tag), do: {tag, []}

  defp resolve_tag(_shape, path, _opts) do
    tag =
      path
      |> Path.basename(Path.extname(path))
      |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1-\\2")
      |> String.replace("_", "-")
      |> String.downcase()

    {tag,
     ["no tag in source — derived #{inspect(tag)} from the filename; pass --tag to override"]}
  end

  defp print_shape(shape, warnings) do
    properties = shape["properties"] || []
    events = shape["events"] || []
    slots = shape["slots"] || []
    styles = shape["styles"] || []

    Mix.shell().info("tessera: extracted #{shape["source"]}")
    Mix.shell().info("  tag: #{shape["tag"]}  class: #{shape["class_name"] || "(none)"}")

    Mix.shell().info(
      "  properties: #{length(properties)} " <>
        "(#{Enum.count(properties, &(&1["kind"] == "state"))} state)"
    )

    Enum.each(properties, fn p ->
      Mix.shell().info(
        "    #{p["name"]}: #{p["type"]}#{if p["kind"] == "state", do: " (state)"}" <>
          "#{if p["attribute"] == false, do: " (attribute: false)"}#{if p["reflect"], do: " (reflect)"}"
      )
    end)

    Mix.shell().info("  events: #{Enum.map_join(events, ", ", & &1["name"])}")
    Mix.shell().info("  slots: #{Enum.map_join(slots, ", ", & &1["name"])}")
    Mix.shell().info("  styles: #{length(styles)} css block(s)")

    extraction_warnings = shape["warnings"] || []

    Enum.each(extraction_warnings ++ warnings, fn w ->
      Mix.shell().info("  WARNING: #{w}")
    end)
  end
end
