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
      # snake; attr/prop keys camelCase) with Lit property options + Array
      assert js =~ "count: { type: Number, attribute: false }"
      assert js =~ ~S|label: { type: String, attribute: "custom-label", reflect: true }|
      assert js =~ "items: { type: Array }"

      # constructor defaults from state + attr + prop defaults
      assert js =~ "this.count = 0;"
      assert js =~ ~S|this.label = "Count";|
      assert js =~ "this.items = [];"

      # translated action runs through __tesseraRunAction state flow
      assert js =~ "__action_increment(params = {}, ev = null)"
      assert js =~ "return (() => { return ({ ...state, count: (state.count + 1) }); })();"

      # lifecycle lowering: one method per declared hook, changed snapshot
      assert js =~ "shouldUpdate(changedProperties) {"
      assert js =~ "const changed = Object.fromEntries(changedProperties);"
      assert js =~ "return (state.count < 10);"
      assert js =~ "willUpdate(changedProperties) {"
      assert js =~ "const next = ({ ...state, count: (state.count + 1) });"
      assert js =~ ~S|if (next != null && typeof next === "object") this.__tesseraSetState(next);|
      assert js =~ "firstUpdated(changedProperties) {"
      assert js =~ "updated(changedProperties) {"
      assert js =~ ~S|const next = emit(this, "count-change", {count: state.count});|

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

  describe "property options (lit-parity 1c)" do
    test "no options → bare type entries (pre-1c bytes)" do
      plain = %Spec{
        spec()
        | attrs: [%{name: :label, type: :string, line: 2}],
          state: [%{name: :count, type: :integer, default: 0, line: 3}],
          lifecycle: %{}
      }

      js = LitCodegen.element_module(plain)
      assert js =~ "count: { type: Number }"
      assert js =~ "label: { type: String }"
      refute js =~ "attribute:"
      refute js =~ "reflect:"
      refute js =~ "shouldUpdate"
      refute js =~ "willUpdate"
      refute js =~ "firstUpdated"
      refute js =~ "updated(changedProperties)"
    end

    test "attribute: false disables the attribute; reflect: false is not emitted" do
      opts = %Spec{
        spec()
        | attrs: [%{name: :label, type: :string, attribute: false, reflect: false, line: 2}]
      }

      js = LitCodegen.element_module(opts)
      assert js =~ "label: { type: String, attribute: false }"
      refute js =~ "reflect:"
    end

    test "converter/hasChanged pass through when a spec carries raw JS (not DSL-exposed)" do
      opts = %Spec{
        spec()
        | props: [
            %{
              name: :items,
              type: :list,
              converter: "{ fromAttribute: (v) => JSON.parse(v) }",
              has_changed: "(a, b) => a !== b",
              line: 7
            }
          ]
      }

      js = LitCodegen.element_module(opts)
      assert js =~ "converter: { fromAttribute: (v) => JSON.parse(v) }"
      assert js =~ "hasChanged: (a, b) => a !== b"
    end

    test ":list maps to Array everywhere (state, attr, prop)" do
      lists = %Spec{
        spec()
        | state: [%{name: :queue, type: :list, default: [], line: 3}],
          attrs: [%{name: :tags, type: :list, line: 2}],
          props: [%{name: :items, type: :list, line: 7}]
      }

      js = LitCodegen.element_module(lists)
      assert js =~ "queue: { type: Array }"
      assert js =~ "tags: { type: Array }"
      assert js =~ "items: { type: Array }"
    end
  end

  describe "lifecycle lowering (lit-parity 1c)" do
    test "only declared hooks emit methods, in canonical order" do
      partial = %Spec{spec() | lifecycle: %{updated: %{js: "null", line: 11}}}
      js = LitCodegen.element_module(partial)

      assert js =~ "updated(changedProperties) {"
      refute js =~ "shouldUpdate"
      refute js =~ "willUpdate"
      refute js =~ "firstUpdated"
    end

    test "firstUpdated/updated discard the hook result (no setState, no return)" do
      js = LitCodegen.element_module(spec())
      [_, rest] = String.split(js, "updated(changedProperties) {")
      [updated_body, _] = String.split(rest, "\n          }")

      refute updated_body =~ "__tesseraSetState"
      refute updated_body =~ ~r/^\s*return /m
      assert updated_body =~ "const next = emit"
    end

    test "shouldUpdate returns the hook value verbatim (false freezes the update)" do
      veto = %Spec{spec() | lifecycle: %{should_update: %{js: "false", line: 8}}}
      assert LitCodegen.element_module(veto) =~ "return false;"
    end
  end

  describe "empty properties (template-only component regression)" do
    # A template-bearing component with ZERO attrs/props/state used to emit
    # `static properties = { , }` (a SyntaxError). It must emit a valid `{}`.
    defp bare_spec do
      %Spec{spec() | attrs: [], props: [], state: [], actions: [], lifecycle: %{}}
    end

    test "no attrs/props/state emits a valid empty object, never { , }" do
      js = LitCodegen.element_module(bare_spec())
      assert js =~ "static properties = {};"
      refute js =~ "{ , }"
      refute js =~ "{\n      ,"
    end

    test "the template-only element module is valid JavaScript (node --check)" do
      js = LitCodegen.element_module(bare_spec())
      dir = Path.join(System.tmp_dir!(), "tessera-empty-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      path = Path.join(dir, "bare.element.generated.mjs")
      File.write!(path, js)

      # node is the WTR runtime dep; when present, prove the bytes parse as ESM.
      # The substring assertion above is the unconditional regression guard.
      if System.find_executable("node") do
        {out, status} = System.cmd("node", ["--check", path], stderr_to_stdout: true)
        assert status == 0, "node --check rejected the generated module:\n#{out}"
      end
    end
  end

  describe "directive imports (lit-parity 1d)" do
    test "no directives → plain lit import, no directive subpath imports" do
      js = LitCodegen.element_module(spec())
      assert js =~ ~S|import { LitElement, html, css } from "lit";|
      refute js =~ "lit/directives/"
      refute js =~ ~S|import { LitElement, html, css, nothing }|
    end

    test "each directive import (and nothing) is emitted when used" do
      with_dir = %Spec{
        spec()
        | template: %{
            lexer: :minimal,
            raw: "x",
            line: 6,
            render_js:
              ~S|html`<div class=${classMap({a: true})} style=${styleMap({color: "red"})} title=${ifDefined(this.x)}>${nothing}</div>`|
          }
      }

      js = LitCodegen.element_module(with_dir)
      assert js =~ ~S|import { LitElement, html, css, nothing } from "lit";|
      assert js =~ ~S|import { classMap } from "lit/directives/class-map.js";|
      assert js =~ ~S|import { styleMap } from "lit/directives/style-map.js";|
      assert js =~ ~S|import { ifDefined } from "lit/directives/if-defined.js";|
    end

    test "a single directive imports only its own module" do
      only_class = %Spec{
        spec()
        | template: %{
            lexer: :minimal,
            raw: "x",
            line: 6,
            render_js: ~S|html`<div class=${classMap({a: true})}></div>`|
          }
      }

      js = LitCodegen.element_module(only_class)
      assert js =~ ~S|import { classMap } from "lit/directives/class-map.js";|
      refute js =~ "style-map.js"
      refute js =~ "if-defined.js"
      refute js =~ ~S|import { LitElement, html, css, nothing }|
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

  describe "derived element module (EXTENSION-CONTRACT.md §5.8, X-16 lowering)" do
    defp derived_spec, do: Tessera.TestFixtures.DerivedWidgetSpec.spec()

    test "matches the derived golden fixture byte-for-byte" do
      golden = File.read!(Path.join(__DIR__, "../../../fixtures/derived_widget.element.golden.mjs"))
      assert LitCodegen.element_module(derived_spec()) == golden
    end

    test "extends the base class re-mixed with the merged contract; imports the base" do
      js = LitCodegen.element_module(derived_spec())

      assert js =~ "class DerivedWidget extends TesseraElement(WidgetBase, contract)"
      assert js =~ ~S|import { WidgetBase } from "./widget-base.element.generated.mjs"|
      assert js =~ ~S|import contract from "./derived_widget.contract.generated.mjs"|
      # base artifacts are referenced, never re-emitted
      refute js =~ "const baseStyles"
    end

    test "only new/overridden reactive properties are emitted (inherited ride the chain)" do
      js = LitCodegen.element_module(derived_spec())

      assert js =~ "extra: { type: Number }"
      assert js =~ "badge: { type: String }"
      # inherited label/count are NOT redeclared
      refute js =~ "label: { type: String }"
      refute js =~ "count: { type: Number }"
    end

    test "styles compose explicitly over the base array (#82 — Lit does not auto-inherit)" do
      js = LitCodegen.element_module(derived_spec())
      assert js =~ "[\n    ...WidgetBase.styles,\n    css`"
      assert js =~ ":host { border: 1px solid var(--derived-widget-accent, #6cf); }"
    end

    test "constructor sets only NEW defaults; state snapshot is the merged keys" do
      js = LitCodegen.element_module(derived_spec())
      assert js =~ "this.extra = 0;"
      assert js =~ ~s|this.badge = "";|
      refute js =~ "this.count = 0;"
      assert js =~ "return { count: this.count, extra: this.extra };"
    end

    test "overridden action down-calls via real ES super; new action has no down-call" do
      js = LitCodegen.element_module(derived_spec())
      assert js =~ "let state = this.__tesseraState();"
      assert js =~ "(state = super.__action_increment(params, ev))"
      assert js =~ "__action_bump(params = {}, ev = null)"
      # inherited decrement-style methods are not re-emitted; only increment+bump
      assert js =~ "__action_increment"
      refute js =~ "__action_decrement"
    end

    test "a fresh (non-derived) spec still lowers through the fresh path" do
      js = LitCodegen.element_module(spec())
      assert js =~ "class SpikeWidget extends TesseraElement(LitElement, contract)"
      assert js =~ "const baseStyles = css`"
    end
  end
end
