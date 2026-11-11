defmodule Noizu.Tessera.InstallerTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.Installer

  @additions Installer.additions("../deps/noizu_tessera/priv/js")

  describe "find_npm/1" do
    test "errors with actionable guidance when npm is missing (injectable lookup)" do
      assert {:error, msg} = Installer.find_npm(fn _cmd -> nil end)
      assert msg =~ "npm was not found"
      assert msg =~ "--no-npm", "points at the skip-the-npm-leg escape hatch"
      assert msg =~ "mix tessera.install"
    end

    test "returns the resolved path when npm exists (injectable lookup)" do
      assert {:ok, "/usr/local/bin/npm"} = Installer.find_npm(fn _cmd -> "/usr/local/bin/npm" end)
    end
  end

  describe "relative_path/2" do
    @tag :tmp_dir
    test "target under the assets dir stays a plain relative path", %{tmp_dir: tmp_dir} do
      assets = Path.join(tmp_dir, "host/assets")
      dep = Path.join(tmp_dir, "host/assets/node_modules/dep/priv/js")

      assert Installer.relative_path(assets, dep) ==
               {:ok, Path.relative_to(dep, assets)}
    end

    @tag :tmp_dir
    test "sibling trees traverse with .. segments (dep outside the app tree)", %{tmp_dir: tmp_dir} do
      assets = Path.join([tmp_dir, "host", "assets"])
      dep = Path.join([tmp_dir, "elsewhere", "dep", "priv", "js"])

      assert {:ok, rel} = Installer.relative_path(assets, dep)
      assert rel == Path.join(["..", "..", "elsewhere", "dep", "priv", "js"])

      # Round-trips back to the target from the assets dir (and is genuinely
      # relative — the old Path.relative_to fallback returned the absolute
      # path for targets outside the assets tree).
      refute String.starts_with?(rel, "/")
      assert Path.expand(rel, assets) == Path.expand(dep)
    end

    test "errors loudly when the paths share no root (different volume)" do
      # Deterministic on every platform: a non-"/" first segment is a foreign
      # root (windows drive or backslash path), so no relative path exists.
      assert {:error, msg} = Installer.relative_path("/app/assets", "D:\\other\\dep")
      assert msg =~ "do not share a root"
      assert msg =~ "relative `file:` path"
    end
  end

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

      # A REAL relative path from the host's assets dir, including `..`
      # traversal for deps living outside the app tree (the old
      # Path.relative_to/2 fallback silently produced a host-absolute path).
      expected_rel =
        case Installer.relative_path(assets, Path.join(dep_app, "priv/js")) do
          {:ok, rel} -> rel
          {:error, msg} -> flunk("expected a relative path, got: #{msg}")
        end

      assert entries == [{"@acme/widgets", "file:" <> expected_rel}]

      refute String.starts_with?(expected_rel, "/"),
             "the file: path must be relative, got: #{expected_rel}"
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

  describe "core_js_dir/2" do
    @tag :tmp_dir
    test "resolves through deps_paths when the dep is registered (transitive path deps)",
         %{tmp_dir: tmp_dir} do
      root = Path.join(tmp_dir, "tessera_checkout")
      File.mkdir_p!(Path.join([root, "priv", "js"]))

      assert {:ok, dir} = Installer.core_js_dir(%{noizu_tessera: root}, "/some/other/deps")
      assert dir == Path.join([Path.expand(root), "priv", "js"])
    end

    @tag :tmp_dir
    test "falls back to the conventional deps/noizu_tessera join", %{tmp_dir: tmp_dir} do
      deps_path = Path.join(tmp_dir, "deps")
      File.mkdir_p!(Path.join([deps_path, "noizu_tessera", "priv", "js"]))

      assert {:ok, dir} = Installer.core_js_dir(%{}, deps_path)
      assert dir == Path.join([deps_path, "noizu_tessera", "priv", "js"])
    end

    @tag :tmp_dir
    test "errors when neither path ships priv/js", %{tmp_dir: tmp_dir} do
      assert Installer.core_js_dir(%{}, Path.join(tmp_dir, "nowhere")) == :error
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
