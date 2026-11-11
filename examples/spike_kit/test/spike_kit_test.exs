defmodule SpikeKitTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.Spec

  describe "package inventory" do
    test "components/0 lists every spike component" do
      assert SpikeKit.components() == [
               SpikeKit.Counter,
               SpikeKit.ToggleChip,
               SpikeKit.StylesPanel
             ]
    end
  end

  describe "SpikeKit.Counter spec (element DSL)" do
    test "carries state, actions and the parsed template" do
      spec = SpikeKit.Counter.__tessera_spec__()

      assert spec.tag == "spike-counter"
      assert [%{name: :count, type: :integer, default: 0}] = spec.state
      assert Enum.map(spec.actions, & &1.name) == [:increment, :decrement]

      assert %{
               lexer: :minimal,
               render_js: render_js
             } = spec.template

      # The template rendered to a lit-html render() body: interpolations,
      # event bindings routed at the translated actions.
      assert render_js =~ "html`"
      assert render_js =~ "${__t(this.label)}"
      assert render_js =~ ~S|@click=${(ev) => this.__tesseraRunAction("increment", {}, ev)}|
    end

    test "actions translate to JS (IIFE: emit + next state)" do
      spec = SpikeKit.Counter.__tessera_spec__()
      increment = Enum.find(spec.actions, &(&1.name == :increment))

      assert increment.js =~
               ~S|emit(this, "count-change", {count: (state.count + this.step), delta: this.step})|

      assert increment.js =~ "{ ...state, count: (state.count + this.step) }"
    end

    test "generated element + wrapper modules are written next to the .ex" do
      dir = __DIR__ |> Path.join("../lib/spike_kit") |> Path.expand()

      assert File.exists?(Path.join(dir, "spike-counter.element.generated.mjs"))
      assert File.exists?(Path.join(dir, "spike-toggle-chip.element.generated.mjs"))
      assert File.exists?(Path.join(dir, "spike_counter.contract.generated.mjs"))
    end
  end

  describe "SpikeKit.ToggleChip spec (element DSL)" do
    test "emits camelCase detail keys at the emit boundary" do
      spec = SpikeKit.ToggleChip.__tessera_spec__()
      toggle = Enum.find(spec.actions, &(&1.name == :toggle))

      assert toggle.js =~ ~s{chipId: this.chipId}

      assert [%{name: "chip-select", detail: %{chip_id: :string, selected: :boolean}}] =
               spec.events
    end

    test "manifest exposes state/actions/template" do
      %{"state" => state, "actions" => actions, "template" => template} =
        Spec.to_manifest_map(SpikeKit.ToggleChip.__tessera_spec__())

      assert %{"name" => "selected", "type" => "boolean"} =
               Enum.find(state, &(&1["name"] == "selected"))

      assert actions == ["toggle"]
      assert template["lexer"] == "minimal"
      assert template["raw"] =~ "{%if @selected}"
    end
  end

  describe "SpikeKit.StylesPanel spec (styles DSL)" do
    test "styles compose in declaration order: shared module then two css blocks" do
      spec = SpikeKit.StylesPanel.__tessera_spec__()

      assert Enum.map(spec.styles, & &1.kind) == [:shared, :css, :css]
      assert Enum.at(spec.styles, 0).value == "./shared_styles.mjs"
      assert Enum.at(spec.styles, 1).value =~ ":host([tone=\"dark\"])"
      assert Enum.at(spec.styles, 1).value =~ "::slotted(p)"
      assert Enum.at(spec.styles, 2).value =~ "var(--tsr-spike-styles-panel-gap, 4px)"
    end

    test "CEM declares the tag-scoped custom properties with fallbacks and the parts" do
      cem = Noizu.Tessera.Codegen.cem([SpikeKit.StylesPanel.__tessera_spec__()])
      [declaration] = cem["modules"] |> hd() |> Map.fetch!("declarations")

      assert declaration["cssCustomProperties"] == [
               %{"name" => "--tsr-spike-styles-panel-accent", "default" => "#6cf"},
               %{"name" => "--tsr-spike-styles-panel-gap", "default" => "4px"},
               %{"name" => "--tsr-spike-styles-panel-padding", "default" => "8px"},
               %{"name" => "--tsr-spike-styles-panel-slotted", "default" => "#c0c"}
             ]

      assert declaration["parts"] == [
               %{"name" => "root"},
               %{"name" => "row"},
               %{"name" => "accent"}
             ]
    end

    test "generated element + shared module live next to the .ex" do
      dir = __DIR__ |> Path.join("../lib/spike_kit") |> Path.expand()

      assert File.exists?(Path.join(dir, "spike-styles-panel.element.generated.mjs"))
      assert File.exists?(Path.join(dir, "shared_styles.mjs"))

      element = File.read!(Path.join(dir, "spike-styles-panel.element.generated.mjs"))
      assert element =~ ~s|import { styles as __tsrSharedStyles0 } from "./shared_styles.mjs";|
      assert element =~ "static styles = ["
    end
  end
end
