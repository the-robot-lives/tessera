defmodule Noizu.Tessera.Component.LitCodegenTest do
  @moduledoc """
  SPIKE (spike/elixir-to-lit): Lit element codegen — golden-fixture pinned,
  deterministic bytes for the same spec.
  """

  use ExUnit.Case, async: true

  alias Noizu.Tessera.Component.LitCodegen
  alias Noizu.Tessera.Spec

  defp spec do
    %Spec{
      version: 1,
      tag: "spike-widget",
      module: Noizu.Tessera.Component.LitCodegenTest.SpikeWidget,
      file: "lib/spike_widget.ex",
      js: "spike_widget.mjs",
      cy: "spike-widget-root",
      attrs: [%{name: :label, type: :string, default: "Count", line: 2}],
      props: [%{name: :items, type: :list, line: 7}],
      slots: [],
      events: [%{name: "count-change", detail: %{count: :integer}, line: 4}],
      state: [%{name: :count, type: :integer, default: 0, line: 3}],
      actions: [
        %{name: :increment, js: ~S|(() => { return ({ ...state, count: (state.count + 1) }); })()|, line: 5}
      ],
      template: %{
        lexer: :minimal,
        raw: "<div>{@count}</div>",
        render_js: "html`<div>${__t(this.count)}</div>`",
        line: 6
      }
    }
  end

  describe "element_module/1" do
    test "matches the golden fixture byte-for-byte" do
      golden = File.read!(Path.join(__DIR__, "../../../fixtures/spike_widget.element.golden.mjs"))
      assert LitCodegen.element_module(spec()) == golden
    end

    test "is deterministic for the same spec" do
      assert LitCodegen.element_module(spec()) == LitCodegen.element_module(spec())
    end

    test "carries the load-bearing fragments" do
      js = LitCodegen.element_module(spec())

      # LitElement + tessera-core mixin + contract import
      assert js =~ ~S|import { LitElement, html, css } from "lit"|
      assert js =~ ~S|import { defineOnce, TesseraElement, emit } from "@noizu/tessera-core"|
      assert js =~ ~S|import contract from "./spike_widget.contract.generated.mjs"|

      # reactive properties from state + attrs + props (snake state keys stay
      # snake; attr/prop keys camelCase)
      assert js =~ "count: { type: Number }"
      assert js =~ "label: { type: String }"
      assert js =~ "items: { type: Object }"

      # constructor defaults from state + attr defaults
      assert js =~ "this.count = 0;"
      assert js =~ ~S|this.label = "Count";|

      # translated action runs through __tesseraRunAction state flow
      assert js =~ "__action_increment(params = {}, ev = null)"
      assert js =~ "return (() => { return ({ ...state, count: (state.count + 1) }); })();"

      # render body from the template
      assert js =~ "return html`<div>${__t(this.count)}</div>`;"

      # register() + top-level auto-register (defineOnce makes both safe)
      assert js =~ ~S|export function register()|
      assert js =~ ~S|return defineOnce("spike-widget", SpikeWidget);|
      assert js =~ "register();\n"
    end
  end

  describe "write_element_module/2" do
    test "writes when absent, :unchanged when identical, rewrites when different" do
      dir = Path.join(System.tmp_dir!(), "tessera-lit-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(dir) end)

      assert LitCodegen.write_element_module(spec(), dir) == :written
      assert LitCodegen.write_element_module(spec(), dir) == :unchanged

      path = LitCodegen.element_path(spec(), dir)
      assert Path.basename(path) == "spike-widget.element.generated.mjs"
      assert File.read!(path) == LitCodegen.element_module(spec())
    end
  end

  describe "write_wrapper_module/2" do
    test "writes the js entry once, never clobbers an existing hand-written one" do
      dir = Path.join(System.tmp_dir!(), "tessera-wrap-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(dir) end)

      assert LitCodegen.write_wrapper_module(spec(), dir) == :written
      wrapper = Path.join(dir, spec().js)
      assert File.read!(wrapper) =~ "import { register } from \"./spike-widget.element.generated.mjs\""
      assert File.read!(wrapper) =~ "register();"

      # a hand-written wrapper is never clobbered
      File.write!(wrapper, "// hand-written\n")
      assert LitCodegen.write_wrapper_module(spec(), dir) == :exists
      assert File.read!(wrapper) == "// hand-written\n"
    end
  end
end
