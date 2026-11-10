defmodule Noizu.Tessera.ScaffoldTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.Scaffold

  describe "camelize_tag/1 + default_module/2" do
    test "persona-card → PersonaCard" do
      assert Scaffold.camelize_tag("persona-card") == "PersonaCard"
      assert Scaffold.camelize_tag("kpi-widget") == "KpiWidget"
    end

    test "default module is <AppCamel>.Components.<CamelTag>" do
      assert Scaffold.default_module(:my_hologram_app, "persona-card") ==
               "MyHologramApp.Components.PersonaCard"
    end
  end

  describe "spec_module_content/2" do
    test "renders a compilable spec module skeleton" do
      content = Scaffold.spec_module_content("persona-card", "MyApp.Components.PersonaCard")

      assert content =~ "defmodule MyApp.Components.PersonaCard do"

      assert content =~
               ~s(use Noizu.Tessera.Component, tag: "persona-card", js: "persona_card.mjs")

      assert content =~ "attr :label, :string, required: true"
      assert content =~ ~s(event "persona-card-changed")
      # heredoc-nesting sanity: the scaffold's own moduledoc survives
      assert content =~ "@moduledoc"
    end
  end

  describe "mjs_content/1" do
    test "imports only exports that exist in @noizu/tessera-core" do
      # defineOnce + TesseraElement are pinned against the real core index in
      # registry_test; this pins the scaffold text to them.
      content = Scaffold.mjs_content("persona-card")
      assert content =~ ~s(import { defineOnce, TesseraElement } from "@noizu/tessera-core";)
      assert content =~ ~s(import contract from "./persona_card.contract.generated.mjs";)
      assert content =~ "class PersonaCard extends TesseraElement(HTMLElement, contract)"
      assert content =~ "export function register()"
      assert content =~ "defineOnce(\"persona-card\", PersonaCard)"
    end
  end

  describe "test_content/2" do
    test "imports register (the only export) and asserts define-once semantics" do
      content = Scaffold.test_content("persona-card", "../../lib/persona_card.mjs")
      assert content =~ ~s(import { register } from "../../lib/persona_card.mjs";)
      assert content =~ ~s(import { defineOnce } from "@noizu/tessera-core";)
      assert content =~ "const ctor = register();"
    end
  end

  describe "generate/3" do
    test "builds the three files at the right paths" do
      files = Scaffold.generate("persona-card", "MyApp.Components.PersonaCard", "/proj")

      paths = Enum.map(files, &elem(&1, 0))

      assert paths == [
               "/proj/lib/my_app/components/persona_card.ex",
               "/proj/lib/my_app/components/persona_card.mjs",
               "/proj/test/components/persona_card_test.mjs"
             ]
    end

    test "raises CompileError on a grammar-invalid tag" do
      assert_raise CompileError, ~r/invalid tessera tag/, fn ->
        Scaffold.generate("BadTag", "X.Y", "/proj")
      end
    end
  end
end
