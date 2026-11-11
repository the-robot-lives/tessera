defmodule Noizu.Tessera.GalleryTest do
  use ExUnit.Case, async: false

  alias Noizu.Tessera.Gallery

  @root Path.expand("../../..", __DIR__)
  @package Tessera.TestFixtures.Package

  defp generate(opts \\ []) do
    Gallery.generate(@package, @root, Keyword.merge([tessera_root: @root], opts))
  end

  defp file!(files, name) do
    {path, content} = Enum.find(files, fn {path, _} -> Path.basename(path) == name end)
    {path, content}
  end

  test "generates the gallery file set under the out dir" do
    files = generate(out: "gallery")
    names = Enum.map(files, fn {path, _} -> Path.basename(path) end) |> Enum.sort()

    assert names ==
             Enum.sort(
               ~w(index.html main.mjs custom-elements.json package.json serve.mjs .gitignore)
             )

    assert Enum.all?(files, fn {path, _} -> String.contains?(path, "/gallery/") end)
  end

  test "main.mjs imports the runtime, the chrome and every component .mjs" do
    files = generate()
    {main_path, main} = file!(files, "main.mjs")
    src_dir = Path.dirname(main_path)

    assert main =~ "import { mountGallery } from"
    assert main =~ "gallery.mjs"
    assert main =~ "gallery.css"
    assert main =~ "mountGallery({ cemUrl: \"./custom-elements.json\" })"

    # Every relative import must resolve to a real file on disk.
    for rel <-
          Regex.scan(~r/import\s+(?:\{[^}]*\}\s+from\s+)?"([^"]+)";/, main,
            capture: :all_but_first
          )
          |> List.flatten() do
      resolved = Path.expand(rel, src_dir)
      assert File.exists?(resolved), "import #{rel} does not resolve (#{resolved})"
    end

    # The fixture component's colocated element is imported.
    assert main =~ "persona_card.mjs"
  end

  test "custom-elements.json is the package CEM" do
    files = generate()
    {_, cem_json} = file!(files, "custom-elements.json")

    assert cem_json == Jason.encode!(@package.cem(), pretty: true) <> "\n"
    cem = Jason.decode!(cem_json)
    assert cem["schemaVersion"] == "1.0.0"
    assert [decl] = hd(cem["modules"])["declarations"]
    assert decl["tagName"] == "persona-card"
  end

  test "index.html wires the bundle, the chrome and the gallery root" do
    {_, html} = file!(generate(), "index.html")

    assert html =~ ~s(<script type="module" src="./dist/bundle.js">)
    assert html =~ ~s(<link rel="stylesheet" href="./dist/bundle.css" />)
    assert html =~ ~s(<main id="gallery" data-cy="gallery">)
    assert html =~ ~s(data-cy="gallery-title")
    assert html =~ "Tessera.TestFixtures.Package"
  end

  test "package.json points the core file: dep at the tessera priv/js" do
    files = generate()
    {pkg_path, pkg_json} = file!(files, "package.json")
    pkg = Jason.decode!(pkg_json)

    assert pkg["name"] == "tessera_test_fixtures_package-gallery"
    assert pkg["scripts"]["build"] =~ "esbuild src/main.mjs --bundle"
    assert pkg["scripts"]["serve"] == "node serve.mjs"

    core = pkg["dependencies"]["@noizu/tessera-core"]
    assert "file:" <> rel = core
    resolved = Path.expand(rel, Path.dirname(pkg_path))
    assert File.exists?(Path.join(resolved, "package.json"))

    assert Jason.decode!(File.read!(Path.join(resolved, "package.json")))["name"] ==
             "@noizu/tessera-core"
  end

  test "serve.mjs defaults to port 5588 and serves json" do
    {_, serve} = file!(generate(), "serve.mjs")
    assert serve =~ "process.env.PORT || 5588"
    assert serve =~ ~s(".json": "application/json)
  end

  test "honors a custom out dir and app name" do
    files = generate(out: "priv/static/gallery", app: :persona_kit)
    assert Enum.all?(files, fn {path, _} -> String.contains?(path, "/priv/static/gallery/") end)
    {_, pkg} = file!(files, "package.json")
    assert Jason.decode!(pkg)["name"] == "persona_kit-gallery"
  end

  test "raises when a component declares no :js" do
    id = :erlang.unique_integer([:positive])

    Code.compile_string(
      """
      defmodule Tessera.Inline.GNoJs#{id} do
        use Noizu.Tessera.Component, tag: "no-js-#{id}"
      end

      defmodule Tessera.Inline.GPkg#{id} do
        use Noizu.Tessera.Package, components: [Tessera.Inline.GNoJs#{id}]
      end
      """,
      Path.join(System.tmp_dir!(), "tessera_gallery_nojs_#{id}.ex")
    )

    package = String.to_atom("Elixir.Tessera.Inline.GPkg#{id}")

    assert_raise ArgumentError, ~r/declares no :js/, fn ->
      Gallery.generate(package, @root, tessera_root: @root)
    end
  end
end
