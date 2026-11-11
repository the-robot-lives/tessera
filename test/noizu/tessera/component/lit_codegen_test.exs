defmodule Noizu.Tessera.Component.LitCodegenTest do
  @moduledoc """
  SPIKE (spike/elixir-to-lit): Lit element codegen — golden-fixture pinned,
  deterministic bytes for the same spec.
  """

  use ExUnit.Case, async: true

  alias Noizu.Tessera.Component.LitCodegen
  alias Noizu.Tessera.Spec

  # The spec lives in test/support so `mix tessera.golden` regenerates the
  # element golden from the SAME spec these tests pin.
  defp spec, do: Tessera.TestFixtures.SpikeWidgetSpec.spec()

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

  describe "styles composition" do
    test "no author styles → static styles = [baseStyles] with the :host defaults" do
      js = LitCodegen.element_module(spec())

      assert js =~ "static styles = [baseStyles];"
      assert js =~ "const baseStyles = css`"

      assert js =~
               ":host {\n  display: block;\n  font-family: system-ui, -apple-system, sans-serif;\n}"
    end

    test "author css blocks and shared modules compose in declaration order, base first" do
      styled = %Spec{
        spec()
        | styles: [
            %{kind: :shared, value: "./shared_styles.mjs", line: 10},
            %{kind: :css, value: ":host { color: red; }", line: 11},
            %{kind: :css, value: ".x { gap: 4px; }", line: 12}
          ]
      }

      js = LitCodegen.element_module(styled)

      assert js =~
               "static styles = [\n    baseStyles,\n    __tsrSharedStyles0,\n    css`\n:host { color: red; }\n`,\n    css`\n.x { gap: 4px; }\n`,\n  ];"

      assert js =~ ~s|import { styles as __tsrSharedStyles0 } from "./shared_styles.mjs";|
    end

    test "a repeated shared path imports once and joins the array at each position" do
      styled = %Spec{
        spec()
        | styles: [
            %{kind: :shared, value: "./s.mjs", line: 10},
            %{kind: :css, value: "a{}", line: 11},
            %{kind: :shared, value: "./s.mjs", line: 12}
          ]
      }

      js = LitCodegen.element_module(styled)

      assert js
             |> String.split(~s|import { styles as __tsrSharedStyles0 } from "./s.mjs";|)
             |> length() == 2

      assert js =~
               "baseStyles,\n    __tsrSharedStyles0,\n    css`\na{}\n`,\n    __tsrSharedStyles0,\n  ];"
    end

    test "distinct shared paths get distinct deterministic bindings" do
      styled = %Spec{
        spec()
        | styles: [
            %{kind: :shared, value: "./a.mjs", line: 10},
            %{kind: :shared, value: "./b.mjs", line: 11}
          ]
      }

      js = LitCodegen.element_module(styled)
      assert js =~ ~s|import { styles as __tsrSharedStyles0 } from "./a.mjs";|
      assert js =~ ~s|import { styles as __tsrSharedStyles1 } from "./b.mjs";|
    end

    test "author CSS is escaped for the css`` literal (backtick, ${, backslash)" do
      styled = %Spec{
        spec()
        | styles: [
            %{kind: :css, value: ~S|.x{content:"`"} .y{content:"${"} .z{content:"\"}|, line: 10}
          ]
      }

      js = LitCodegen.element_module(styled)
      assert js =~ ~S|.x{content:"\`"}|
      assert js =~ ~S|.y{content:"\${"}|
      assert js =~ ~S|.z{content:"\\"}|
    end

    test "the host exposes a root part through connectedCallback (EXTENSION-CONTRACT §7)" do
      js = LitCodegen.element_module(spec())
      assert js =~ "connectedCallback() {\n    super.connectedCallback();"
      assert js =~ ~s|this.setAttribute("part", "root");|
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

      assert File.read!(wrapper) =~
               "import { register } from \"./spike-widget.element.generated.mjs\""

      assert File.read!(wrapper) =~ "register();"

      # a hand-written wrapper is never clobbered
      File.write!(wrapper, "// hand-written\n")
      assert LitCodegen.write_wrapper_module(spec(), dir) == :exists
      assert File.read!(wrapper) == "// hand-written\n"
    end
  end
end
