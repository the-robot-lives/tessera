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
