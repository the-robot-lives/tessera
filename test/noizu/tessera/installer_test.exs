defmodule Noizu.Tessera.InstallerTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.Installer

  @additions Installer.additions("../deps/noizu_tessera/priv/js")

  describe "additions/2" do
    test "wires the core file: dep and lit" do
      assert @additions["@noizu/tessera-core"] == "file:../deps/noizu_tessera/priv/js"
      assert @additions["lit"] == "^3"
    end

    test "merges dep-app file: entries" do
      additions =
        Installer.additions("x", [{"@acme/tessera-widgets", "file:../deps/acme/priv/js"}])

      assert additions["@acme/tessera-widgets"] == "file:../deps/acme/priv/js"
      assert additions["lit"] == "^3"
    end
  end

  describe "merge_package_json/2" do
    test "adds missing keys, keeps existing values, preserves unrelated keys" do
      existing = %{
        "name" => "host-assets",
        "dependencies" => %{"lit" => "^2.0.0", "esbuild" => "^0.21"}
      }

      merged = Installer.merge_package_json(existing, @additions)

      assert merged["name"] == "host-assets"
      assert merged["dependencies"]["lit"] == "^2.0.0"
      assert merged["dependencies"]["esbuild"] == "^0.21"
      assert merged["dependencies"]["@noizu/tessera-core"] == "file:../deps/noizu_tessera/priv/js"
    end

    test "starts a dependencies map when absent" do
      merged = Installer.merge_package_json(%{"name" => "fresh"}, @additions)
      assert merged["dependencies"]["lit"] == "^3"
    end

    test "is idempotent" do
      once = Installer.merge_package_json(%{}, @additions)
      assert Installer.merge_package_json(once, @additions) == once
    end
  end

  describe "dep_js_entries/3" do
    @tag :tmp_dir
    test "collects file: entries from fake dep apps shipping priv/js", %{tmp_dir: tmp_dir} do
      # fake dep app shipping a tessera js runtime
      dep_app = Path.join(tmp_dir, "my_dep_app")
      File.mkdir_p!(Path.join([dep_app, "priv", "js"]))

      File.write!(
        Path.join([dep_app, "priv", "js", "package.json"]),
        ~s({"name":"@acme/widgets"})
      )

      # fake app without a js runtime must be skipped
      bare_app = Path.join(tmp_dir, "bare_app")
      File.mkdir_p!(bare_app)

      assets = Path.join([tmp_dir, "host", "assets"])

      entries =
        Installer.dep_js_entries(%{my_dep_app: dep_app, bare_app: bare_app}, assets, :host_app)

      # relative from the host's assets dir, regardless of where the dep lives
      # (the old starts_with?-assets predicate never matched deps)
      assert entries == [
               {"@acme/widgets",
                "file:" <> Path.relative_to(Path.join(dep_app, "priv/js"), assets)}
             ]
    end

    @tag :tmp_dir
    test "skips the current app", %{tmp_dir: tmp_dir} do
      dep_app = Path.join(tmp_dir, "my_dep_app")
      File.mkdir_p!(Path.join([dep_app, "priv", "js"]))

      File.write!(
        Path.join([dep_app, "priv", "js", "package.json"]),
        ~s({"name":"@acme/widgets"})
      )

      assert Installer.dep_js_entries(%{my_dep_app: dep_app}, "/x/assets", :my_dep_app) == []
    end

    test "returns [] for a deps map without js shippers" do
      assert Installer.dep_js_entries(%{"some_app" => "/nonexistent"}, "/x/assets", nil) == []
    end
  end

  describe "merge_into_assets/2" do
    @tag :tmp_dir
    test "writes once, then reports unchanged", %{tmp_dir: tmp_dir} do
      assert Installer.merge_into_assets(tmp_dir, @additions) == :written

      path = Path.join(tmp_dir, "package.json")
      decoded = path |> File.read!() |> Jason.decode!()

      assert decoded["dependencies"]["@noizu/tessera-core"] ==
               "file:../deps/noizu_tessera/priv/js"

      assert Installer.merge_into_assets(tmp_dir, @additions) == :unchanged
    end

    @tag :tmp_dir
    test "merges into an existing package.json without losing keys", %{tmp_dir: tmp_dir} do
      File.write!(
        Path.join(tmp_dir, "package.json"),
        ~s({"name":"host","dependencies":{"lit":"^2"}})
      )

      assert Installer.merge_into_assets(tmp_dir, @additions) == :written
      decoded = Path.join(tmp_dir, "package.json") |> File.read!() |> Jason.decode!()
      assert decoded["name"] == "host"
      assert decoded["dependencies"]["lit"] == "^2"
      assert Map.has_key?(decoded["dependencies"], "@noizu/tessera-core")
    end
  end
end
