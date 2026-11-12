defmodule Noizu.Tessera.FromLit.GeneratorTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.FromLit.Extractor
  alias Noizu.Tessera.FromLit.Generator
  alias Noizu.Tessera.Hologram.Adapter
  alias Noizu.Tessera.Scaffold
  alias Noizu.Tessera.Spec

  @fixture_dir Path.expand("../../../fixtures/lit", __DIR__)
  @persona Extractor.extract_file(Path.join(@fixture_dir, "persona_widget.ts")) |> elem(1)

  # `render: false` = the pre-render-conversion stub path (spec + hand-portable
  # .mjs element + WTR skeleton); default = the render() -> ~TSR path (spec +
  # WTR skeleton, element generated from the spec at `mix compile`).
  defp generate_persona(
         module_name \\ "MyApp.Components.PersonaWidget",
         root \\ "/proj",
         opts \\ []
       ) do
    Generator.generate(@persona, module_name, root, opts)
  end

  defp spec_content({files, _warnings}), do: files |> Enum.at(0) |> elem(1)
  defp mjs_content({files, _warnings}), do: files |> Enum.at(1) |> elem(1)

  describe "file layout" do
    test "mirrors tessera.gen.component paths in stub mode (spec + colocated .mjs + WTR skeleton)" do
      {files, _warnings} =
        generate_persona("MyApp.Components.PersonaWidget", "/proj", render: false)

      assert Enum.map(files, &elem(&1, 0)) ==
               Enum.map(
                 Scaffold.generate("persona-widget", "MyApp.Components.PersonaWidget", "/proj"),
                 &elem(&1, 0)
               )
    end

    test "render() conversion mode drops the .mjs stub (element generated from the spec)" do
      {files, _warnings} = generate_persona()

      assert Enum.map(files, &elem(&1, 0)) ==
               Enum.map(
                 Scaffold.generate("persona-widget", "MyApp.Components.PersonaWidget", "/proj"),
                 &elem(&1, 0)
               )
               |> Enum.reject(&String.ends_with?(&1, "persona_widget.mjs"))

      assert length(files) == 2
    end

    test "the WTR skeleton is the scaffold one, importing the real relative .mjs path" do
      {files, _warnings} =
        generate_persona("MyApp.Components.PersonaWidget", "/proj", render: false)

      {test_path, test_content} = Enum.at(files, 2)
      [{_lib, _spec}, {mjs_path, _mjs}, _test] = files

      expected_rel = Path.relative_to(mjs_path, Path.dirname(test_path), force: true)
      assert test_content =~ ~s(import { register } from "#{expected_rel}";)
    end
  end

  describe "spec DSL" do
    test "attribute-observed scalars become attrs with defaults" do
      content = spec_content(generate_persona())

      assert content =~
               ~s(use Noizu.Tessera.Component, tag: "persona-widget", js: "persona_widget.mjs")

      assert content =~ ~s(attr :display_name, :string, default: "Anonymous")
      assert content =~ "attr :click_count, :float, default: 0"
      assert content =~ "attr :disabled, :boolean, default: false"
      assert content =~ ~s(attr :tone, :string, default: "neutral")
      assert content =~ "attr :label, :string"
      assert content =~ "attr :session_id, :string"
    end

    test "complex and attribute:false properties become props (json for list/map)" do
      content = spec_content(generate_persona())

      assert content =~ "prop :tag_list, :list, json: true, default: []"
      assert content =~ "prop :filters, :map, json: true, default: %{}"
    end

    test "stub mode: Lit @state fields are commented-out state declarations, not wire props" do
      content =
        spec_content(generate_persona("MyApp.Components.PersonaWidget", "/proj", render: false))

      assert content =~ "# state :open, :boolean, default: false"
      assert content =~ "# state :internal_count, :integer, default: 0"
      refute content =~ ~r/^\s*prop :open/m
      refute content =~ ~r/^\s*attr :open/m
    end

    test "render() conversion mode: @state fields become real state declarations the template reads" do
      content = spec_content(generate_persona())

      assert content =~ "state :open, :boolean, default: false"
      assert content =~ "state :internal_count, :integer, default: 0"
      assert content =~ "template(~TSR\"\"\""
    end

    test "events carry snake_cased detail maps; grammar adaptations are loud" do
      {files, warnings} = generate_persona()
      content = spec_content({files, warnings})

      assert content =~
               ~s(event "persona-select", detail: %{active: :boolean, click_count: :integer, persona_id: :string})

      assert content =~ ~s(event "focus-changed", detail: %{source: :any})
      assert content =~ ~s(event "persona-widget-close")

      assert Enum.any?(warnings, &(&1 =~ ~s(event "focusChanged")))
      assert Enum.any?(warnings, &(&1 =~ ~s(event "close")))
      # the adaptations are embedded in the generated moduledoc, not just printed
      assert content =~ "Conversion warnings (verify by hand):"
      assert content =~ "STUB"
    end

    test "slots and the cy hook are emitted" do
      content = spec_content(generate_persona())

      assert content =~ ~s(\n  slot "header")
      assert content =~ ~s(\n  slot "default")
      assert content =~ ~s(\n  slot "footer")
      assert content =~ ~s(cy "persona-widget-root")
    end

    test "extraction warnings are embedded in the moduledoc alongside planning warnings" do
      content = spec_content(generate_persona())

      assert content =~ "tone: Lit option `converter` has no tessera equivalent"
      assert content =~ "sessionId: computed default"
    end

    test "original Lit names and reflect/custom-attribute notes ride along as comments" do
      content = spec_content(generate_persona())

      assert content =~ "# Lit: displayName; reflect; Lit attribute: display-name"
      assert content =~ "# Lit: clickCount"
    end
  end

  describe "compiled contract (verify-the-thing: the emitted DSL really compiles)" do
    @describetag :compile

    test "the generated spec module compiles and exposes the extracted contract" do
      id = System.unique_integer([:positive])
      module_name = "Tessera.FromLitInline.N#{id}"
      {files, _warnings} = generate_persona(module_name)
      path = Path.join(System.tmp_dir!(), "tessera_from_lit_#{id}.ex")

      [{mod, _}] = Code.compile_string(spec_content({files, _warnings}), path)

      assert mod == String.to_atom("Elixir." <> module_name)
      spec = mod.__tessera_spec__()
      assert %Spec{} = spec
      assert spec.tag == "persona-widget"

      assert Enum.map(spec.attrs, & &1.name) ==
               [:display_name, :click_count, :disabled, :tone, :label, :session_id]

      assert Enum.map(spec.props, & &1.name) == [:tag_list, :filters]
      assert Enum.find(spec.props, &(&1.name == :tag_list)).json == true

      assert Enum.map(spec.events, & &1.name) ==
               ["persona-select", "focus-changed", "persona-widget-close"]

      assert Enum.find(spec.events, &(&1.name == "persona-select")).detail ==
               %{active: :boolean, click_count: :integer, persona_id: :string}

      assert Enum.map(spec.slots, & &1.name) == ["header", "default", "footer"]
      assert spec.cy == "persona-widget-root"
    end
  end

  describe ".mjs element stub" do
    test "extends TesseraElement(LitElement, contract) and keeps the load-bearing register" do
      content =
        mjs_content(generate_persona("MyApp.Components.PersonaWidget", "/proj", render: false))

      assert content =~ ~s(import { LitElement, html, css } from "lit";)
      assert content =~ ~s(import { defineOnce, TesseraElement } from "@noizu/tessera-core";)
      assert content =~ ~s(import contract from "./persona_widget.contract.generated.mjs";)
      assert content =~ "class PersonaWidget extends TesseraElement(LitElement, contract)"
      assert content =~ ~s[defineOnce("persona-widget", PersonaWidget)]
      assert Adapter.has_top_level_register?(content)
    end

    test "extracted styles are carried into static styles; state fields are listed for porting" do
      content =
        mjs_content(generate_persona("MyApp.Components.PersonaWidget", "/proj", render: false))

      assert content =~ "static styles = css`"
      assert content =~ ":host { display: block; }"
      assert content =~ "Lit @state to port as internal reactive state: open, internalCount"
    end

    test "interpolated styles are commented out, never emitted as broken JS" do
      shape =
        Extractor.extract("""
        class X extends LitElement {
          static styles = css`:host { color: ${theme.primary}; }`;
        }
        """)
        |> Map.put("tag", "x-widget")

      {files, _warnings} = Generator.generate(shape, "MyApp.XWidget", "/proj")
      content = mjs_content({files, _warnings})

      assert content =~ "// static styles = css`"
      refute content =~ ~r/^\s*static styles = css`/m
      assert content =~ ~s(import { LitElement, html } from "lit";)
    end
  end

  describe "unrepresentable input is skipped loudly" do
    test "names failing the snake grammar / round-trip are skipped with a warning" do
      shape = %{
        "tag" => "x-widget",
        "source" => nil,
        "class_name" => "X",
        "properties" => [
          %{
            "name" => "foo__bar",
            "kind" => "property",
            "type" => "string",
            "default" => nil,
            "default_expression" => nil,
            "attribute" => true,
            "reflect" => false
          }
        ],
        "events" => [],
        "slots" => [],
        "styles" => [],
        "warnings" => []
      }

      {files, warnings} = Generator.generate(shape, "MyApp.XWidget", "/proj")
      content = spec_content({files, warnings})

      # the name may appear in the moduledoc warning — but never as a DSL entry
      refute content =~ ~r/^\s*(attr|prop) :foo__bar/m
      assert Enum.any?(warnings, &(&1 =~ "foo__bar"))
      assert Enum.any?(warnings, &(&1 =~ "round-trip"))
    end

    test "invalid slot names are skipped with a warning" do
      shape = %{
        "tag" => "x-widget",
        "source" => nil,
        "class_name" => "X",
        "properties" => [],
        "events" => [],
        "slots" => [%{"name" => "BadSlot"}],
        "styles" => [],
        "warnings" => []
      }

      {files, warnings} = Generator.generate(shape, "MyApp.XWidget", "/proj")

      refute spec_content({files, warnings}) =~ ~r/^\s*slot "BadSlot"/m
      assert Enum.any?(warnings, &(&1 =~ "slot"))
    end

    test "a grammar-invalid tag raises CompileError" do
      shape = %{@persona | "tag" => "BadTag"}

      assert_raise CompileError, ~r/invalid tessera tag/, fn ->
        Generator.generate(shape, "MyApp.Bad", "/proj")
      end
    end

    test "complex properties with observed attributes warn about the dropped attribute" do
      {_files, warnings} = generate_persona()
      assert Enum.any?(warnings, &(&1 =~ "tagList: complex Lit property ships as a json prop"))
    end
  end
end
