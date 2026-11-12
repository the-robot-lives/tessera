defmodule Noizu.Tessera.FromLit.RenderTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.FromLit.Extractor
  alias Noizu.Tessera.FromLit.Generator
  alias Noizu.Tessera.FromLit.Render

  @fixture_dir Path.expand("../../../fixtures/lit", __DIR__)
  @fixture Path.join(@fixture_dir, "construct_kitchen_sink.ts")

  # shape extracted once (like GeneratorTest's @persona); tag resolved the way
  # `mix tessera.from_lit` does via @customElement in the source.
  @sink @fixture |> Extractor.extract_file() |> elem(1)

  defp generate(module_name \\ "MyApp.Components.KitchenSink", root \\ "/proj") do
    Generator.generate(@sink, module_name, root)
  end

  defp spec_content({files, _warnings}), do: files |> Enum.at(0) |> elem(1)

  defp template_block(content) do
    case Regex.run(~r/~TSR"""\n(.*?)\n\s*"""/s, content) do
      [_, inner] -> inner
      _ -> flunk("no ~TSR template block in generated spec:\n#{content}")
    end
  end

  describe "positive: every converted construct" do
    test "interpolation, ternary, guard-&&, map, repeat, events, bindings, directives" do
      markup = spec_content(generate()) |> template_block()

      # ${this.title} -> {@title}; quoted attribute interpolation
      assert markup =~ ~s[<h1>{@title}</h1>]
      assert markup =~ ~s[aria-label="item {@title}"]
      # classMap -> class_map literal-map form; plain operator expression
      assert markup =~ ~s[class_map(%{active: @open})]
      assert markup =~ ~s[{(@count) + 1}]
      # ternary html -> {%if}/{%else}
      assert markup =~ ~s[{%if @open}<span>open</span>{%else}<span>closed</span>{/if}]
      # && guard -> {%if}
      assert markup =~ ~s[{%if (@count) > 0}<b>big</b>{/if}]
      # .map -> {%for}; repeat -> {%for key:}
      assert markup =~ ~s[{%for item <- @items}<li>{item.name}</li>{/for}]

      assert markup =~
               ~s[{%for item <- @items, key: item.id}<row row-name={item.name}>row</row>{/for}]

      # event binding -> $click action reference
      assert markup =~ ~s[<button $click={:save}>]
      # .prop / ?attr / attr={expr} bindings
      assert markup =~ ~s[.value={@opt_val}]
      assert markup =~ ~s[?disabled={@open}]
      # directives
      assert markup =~ ~s[{live(@live_val)}]
      assert markup =~ ~s[{if_defined(@opt_val)}]
      assert markup =~ ~s[{unsafe_html(@raw_html)}]
      # supported operators + whitelisted methods + untagged template literal
      assert markup =~ ~s[{Enum.count(@items)} items]
      assert markup =~ ~s[{String.upcase(@title)}]
      assert markup =~ ~s[{"tag: \#{@title}"}]
    end

    test "the conversion emits actions for event handlers" do
      content = spec_content(generate())

      assert content =~
               "# Lit handler `save` — port the method body (state/emit DSL); no-op stub."

      assert content =~ "action(:save, fn state, _params -> state end)"
    end
  end

  describe "compiled contract (verify-the-thing: the emitted DSL really compiles)" do
    @describetag :compile

    test "the converted spec module compiles and the template survives the TSR compiler" do
      id = System.unique_integer([:positive])
      module_name = "Tessera.FromLitRender.N#{id}"
      {files, gen_warnings} = generate(module_name)
      path = Path.join(System.tmp_dir!(), "tessera_from_lit_render_#{id}.ex")

      [{mod, _}] = Code.compile_string(spec_content({files, gen_warnings}), path)

      assert mod == String.to_atom("Elixir." <> module_name)
      spec = mod.__tessera_spec__()
      assert %Noizu.Tessera.Spec{} = spec
      assert spec.tag == "kitchen-sink"
      assert template = spec.template
      # the lowered markup survives parse/compile (converted constructs intact)
      assert template.raw =~ ~s[{%for item <- @items, key: item.id}]
      assert template.raw =~ ~s[{%if @open}<span>open</span>{%else}<span>closed</span>{/if}]
      assert template.raw =~ ~s[$click={:save}]
    end
  end

  describe "negative: unsupported constructs become TODOs, never broken markup" do
    test "Render.convert reports a todo for a call outside the subset" do
      %{markup: markup, todos: todos} =
        Render.convert(~s[<x>${this.compute()}</x>], %{"title" => :title})

      assert [%{snippet: "this.compute()", reason: reason}] = todos
      assert reason =~ "method call"
      assert reason =~ "dropped"
      # the construct is dropped, not guessed
      assert markup == "<x></x>"
    end

    test "the generator embeds # TODO(tessera.from_lit) and returns the warning" do
      {files, warnings} = generate()
      content = spec_content({files, warnings})

      assert content =~ "# TODO(tessera.from_lit): "
      assert Enum.any?(warnings, &(&1 =~ "left as a TODO marker in the template"))
    end

    test "unsafeHTML conversion carries an XSS-sink warning todo (PR #44 review, thread 4545471200)" do
      %{markup: markup, todos: todos} =
        Render.convert(~s[<x>${unsafeHTML(this.h)}</x>], %{"h" => :h})

      assert markup =~ "unsafe_html(@h)"
      assert [%{reason: reason}] = todos
      assert reason =~ "XSS sink"
    end

    test "unsafeHTML inside an attribute binding carries the warning too" do
      %{todos: todos} =
        Render.convert(
          ~s[<x .html=${unsafeHTML(this.h)}></x>],
          %{"h" => :h}
        )

      assert Enum.any?(todos, &(&1.reason =~ "XSS sink"))
    end

    test "_save/save handler collision is detected, not silently merged (PR #44 review, thread 4545471212)" do
      %{markup: markup, todos: todos} =
        Render.convert(
          ~s(<button @click=${this._save}></button><button @click=${this.save}></button>),
          %{}
        )

      assert markup =~ "$click={:save}"
      assert [%{reason: reason}] = todos
      assert reason =~ "collapse to tessera action `:save`"
      assert reason =~ "rename one handler"
    end

    test "two bindings to the SAME handler share one action without a collision (PR #76 review, 4551712824)" do
      %{markup: markup, todos: todos, actions: actions} =
        Render.convert(
          ~s(<button @click=${this.save}>a</button><button @click=${this.save}>b</button>),
          %{}
        )

      assert markup == ~s(<button $click={:save}>a</button><button $click={:save}>b</button>)
      assert todos == []
      assert actions == ["save"]
    end

    test "classMap/styleMap with a variable argument is dropped with the precise reason (PR #44 review, thread 4545471218)" do
      %{markup: markup, todos: todos} =
        Render.convert(~s[<p class=${classMap(this.classes)}>x</p>], %{"classes" => :classes})

      assert markup == "<p>x</p>"
      assert [%{reason: reason}] = todos
      assert reason =~ "inline object literal"
    end

    test "guard with variable deps is dropped with the precise reason (PR #44 review, thread 4545471223)" do
      %{markup: markup, todos: todos} =
        Render.convert(
          ~s[<p>${guard(this.items, () => this.n)}</p>],
          %{"items" => :items, "n" => :n}
        )

      assert markup == "<p></p>"
      assert [%{reason: reason}] = todos
      assert reason =~ "literal dep array"
    end

    test "guard with a non-zero-argument arrow names the arrow form in the reason (PR #76 review, 4551712854)" do
      %{markup: markup, todos: todos} =
        Render.convert(
          ~s|<p>${guard([this.n], (x) => x)}</p>|,
          %{"n" => :n}
        )

      assert markup == "<p></p>"
      assert [%{reason: reason}] = todos
      assert reason =~ "zero-argument arrow"
    end

    test "a fully-unsupported render body keeps its todos/warnings (PR #44 review, thread 4545471204)" do
      src = ~S'''
      import { html } from "lit";
      @customElement("x-todo-keep")
      export class XTodoKeep extends LitElement {
        static properties = { n: {} };
        render() {
          return html`${this.compute()}`;
        }
      }
      '''

      path =
        Path.join(System.tmp_dir!(), "tessera_pr44_todo_#{System.unique_integer([:positive])}.ts")

      File.write!(path, src)
      {:ok, shape} = Extractor.extract_file(path)
      {files, warnings} = Generator.generate(shape, "Tessera.FromLitTodoKeep.N1", "/proj")
      content = spec_content({files, warnings})

      assert Enum.any?(warnings, &(&1 =~ "method call"))
      assert content =~ "# TODO(tessera.from_lit): "
      assert content =~ "template(~TSR"

      [{mod, _}] = Code.compile_string(content, path)
      assert %Noizu.Tessera.Spec{} = mod.__tessera_spec__()
    end
  end

  describe "generated-heredoc safety (PR #44 review, thread 4545471208)" do
    @describetag :compile

    defp write_and_extract(src) do
      path =
        Path.join(System.tmp_dir!(), "tessera_pr44_#{System.unique_integer([:positive])}.ts")

      File.write!(path, src)
      {:ok, shape} = Extractor.extract_file(path)
      shape
    end

    defp compile_spec(shape, module_name) do
      {files, gen_warnings} = Generator.generate(shape, module_name, "/proj")
      content = spec_content({files, gen_warnings})
      id = System.unique_integer([:positive])
      path = Path.join(System.tmp_dir!(), "tessera_pr44_spec_#{id}.ex")
      [{mod, _}] = Code.compile_string(content, path)
      {mod.__tessera_spec__(), content, gen_warnings}
    end

    test "a markup line starting with triple quotes cannot break compilation — it is warned and omitted" do
      src = ~S'''
      import { html } from "lit";
      @customElement("x-heredoc")
      export class XHeredoc extends LitElement {
        static properties = { n: {} };
        render() {
          return html`
            <p>
            """ at line start
            </p>
            <p>${this.n}</p>
          `;
        }
      }
      '''

      {spec, content, warnings} =
        write_and_extract(src)
        |> compile_spec("Tessera.FromLitHeredoc.N#{System.unique_integer([:positive])}")

      assert Enum.any?(warnings, &(&1 =~ "line starting with"))
      refute content =~ ~s[template(~TSR]
      assert content =~ "cannot be embedded in a ~TSR heredoc"
      # the module still compiles — that is the fix: the sigil can no longer terminate early
      assert %Noizu.Tessera.Spec{} = spec
    end

    test "mid-line triple quotes stay legal heredoc content (no false positive)" do
      src = ~S'''
      import { html } from "lit";
      @customElement("x-heredoc-mid")
      export class XHeredocMid extends LitElement {
        static properties = { n: {} };
        render() {
          return html`
            <p>a """ b</p>
            <p>${this.n}</p>
          `;
        }
      }
      '''

      {spec, content, warnings} =
        write_and_extract(src)
        |> compile_spec("Tessera.FromLitHeredocMid.N#{System.unique_integer([:positive])}")

      refute Enum.any?(warnings, &(&1 =~ "line starting with"))
      assert content =~ ~s[template(~TSR]
      assert %Noizu.Tessera.Spec{} = spec
    end

    test "a css block with a line-initial triple quote is warned and omitted" do
      src = ~S'''
      import { html, css } from "lit";
      @customElement("x-heredoc-css")
      export class XHeredocCss extends LitElement {
        static styles = css`
          :host { display: block; }
        """
        `;
        render() {
          return html`<p>${this.n}</p>`;
        }
      }
      '''

      {spec, content, warnings} =
        write_and_extract(src)
        |> compile_spec("Tessera.FromLitCssHeredoc.N#{System.unique_integer([:positive])}")

      assert Enum.any?(warnings, &(&1 =~ "line starting with"))
      assert content =~ "cannot be embedded in a ~CSS heredoc"
      assert %Noizu.Tessera.Spec{} = spec
    end
  end

  describe "generated-JS proofs for the N/A threads (PR #44 review, 1185/1189/1193/1197)" do
    @describetag :compile

    test "untagged template literal, &&/||, string +, ==/=== all keep JS semantics in the lowered output" do
      src = ~S'''
      import { html } from "lit";
      @customElement("x-na-proof")
      export class XNaProof extends LitElement {
        static properties = { a: {}, b: {}, n: {} };
        render() {
          return html`
            <p>${`tag: ${this.n}`}</p>
            <p>${this.a && this.b}</p>
            <p>${this.a || this.b}</p>
            <p>${"x" + this.n}</p>
            <p>${this.a === this.b}</p>
            <p>${this.a == this.b}</p>
          `;
        }
      }
      '''

      {spec, _content, _warnings} =
        write_and_extract(src)
        |> compile_spec("Tessera.FromLitNaProof.N#{System.unique_integer([:positive])}")

      render_js = spec.template[:render_js]

      # 1185 — `#{…}` inside ~TSR is TSR expression syntax, not Elixir
      # interpolation (~TSR is an uppercase sigil: no interpolation); Expr
      # lowers the interpolation to a JS template literal.
      assert render_js =~ ~r/tag: \$\{/
      refute render_js =~ ~S[#{]

      # 1189 — and/or lower to JS && / ||: JS truthy semantics are preserved
      # in the generated element (Tier 1 compiles, never evaluates, the
      # markup).
      assert render_js =~ "&&"
      assert render_js =~ "||"

      # 1193 — + lowers to JS +: string concatenation works in the output.
      assert render_js =~ ~r/"x" \+ /

      # 1197 — == and === both lower to strict ===: no loose == remains.
      assert render_js =~ ~r/===.*===/s
      refute render_js =~ ~r/[^=!<>]==[^=]/
    end
  end
end
