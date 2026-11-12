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
  end
end
