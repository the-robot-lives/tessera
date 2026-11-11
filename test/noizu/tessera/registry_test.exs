defmodule Noizu.Tessera.RegistryTest do
  use ExUnit.Case, async: false

  alias Noizu.Tessera.Registry

  test "tessera_apps includes the current app" do
    assert :noizu_tessera in Registry.tessera_apps()
  end

  test "tessera_modules finds the compiled fixture components" do
    modules = Registry.tessera_modules(:noizu_tessera)
    assert Tessera.TestFixtures.PersonaCard in modules
  end

  test "all_modules aggregates across apps, sorted" do
    modules = Registry.all_modules()
    assert Tessera.TestFixtures.Package in modules or Tessera.TestFixtures.PersonaCard in modules
    assert Tessera.TestFixtures.PersonaCard in modules
    assert modules == Enum.sort(modules)
  end

  test "load/1 loads beam modules" do
    assert Registry.load(String)
    refute Registry.load(Tessera.Definitely.Not.There)
  end

  test "package_modules finds compiled packages, not plain components" do
    packages = Registry.package_modules(:noizu_tessera)
    assert Tessera.TestFixtures.Package in packages
    refute Tessera.TestFixtures.PersonaCard in packages
  end

  test "all_package_modules aggregates across apps, sorted" do
    packages = Registry.all_package_modules()
    assert Tessera.TestFixtures.Package in packages
    assert packages == Enum.sort(packages)
  end

  test "resolve_package/1 resolves by name and rejects non-packages" do
    assert {:ok, Tessera.TestFixtures.Package} =
             Registry.resolve_package("Tessera.TestFixtures.Package")

    assert {:error, message} = Registry.resolve_package("String")
    assert message =~ "not a loaded tessera package"

    assert {:error, message} = Registry.resolve_package("Tessera.Definitely.Not.There")
    assert message =~ "not a loaded tessera package"
  end

  test "resolve_package(nil) finds the current project's single package" do
    assert {:ok, Tessera.TestFixtures.Package} = Registry.resolve_package(nil)
  end

  test "app_js_package returns nil for apps without a tessera JS runtime" do
    # hologram is a real dep of this project but ships no priv/js/package.json
    assert Registry.app_js_package(:hologram) == nil
    assert Registry.app_js_package(:definitely_not_a_dep_xyz) == nil
  end

  test "the JS core index exports every symbol the scaffold imports" do
    index = File.read!(Path.expand("../../../priv/js/src/index.mjs", __DIR__))
    assert index =~ "export { defineOnce }"
    assert index =~ "export { TesseraElement }"
    assert index =~ "export { emit"
    assert index =~ "export { behaviors"
  end
end
