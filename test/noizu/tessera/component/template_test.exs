defmodule Noizu.Tessera.Component.TemplateTest do
  @moduledoc """
  SPIKE (spike/elixir-to-lit): template pipeline — parse (dual lexer), treeify,
  lit-html emission. The root repo compiles with the optional Hologram dep, so
  these run the `:hologram` lexer; the minimal fallback lexer is exercised by
  `examples/spike_kit` (compiled without Hologram).
  """

  use ExUnit.Case, async: true

  alias Noizu.Tessera.Component.{Expr, Template}

  defp ctx do
    %Expr{
      state_keys: MapSet.new([:count, :selected, :clicks]),
      attrs: %{label: :string, step: :integer},
      props: %{items: :list},
      events: MapSet.new(["count-change", "chip-select"]),
      actions: MapSet.new([:increment, :toggle]),
      module: __MODULE__,
      file: __ENV__.file,
      line: 1
    }
  end

  defp render!(markup) do
    {:ok, tree} = Template.parse(markup)
    Template.to_lit_render(tree, ctx())
  end

  # -- dual-lexer parity helpers ----------------------------------------------
  # The root suite runs the :hologram lexer via parse/1; minimal_lex/1 +
  # treeify/3 build the minimal-lexer tree for the same markup. Attribute
  # value shapes differ cosmetically between lexers ({:static, s} vs
  # {:parts, [{:text, s}]}) — normalize to compare semantics.

  defp minimal_tree(markup) do
    {:ok, tokens} = Template.minimal_lex(markup)
    {:ok, tree} = Template.treeify(tokens, [], [])
    tree
  end

  defp walk({:element, _tag, _attrs, children} = node, acc),
    do: Enum.reduce(children, [node | acc], &walk/2)

  defp walk({:fragment, children}, acc), do: Enum.reduce(children, acc, &walk/2)
  defp walk({:if, _ast, then_c, else_c}, acc), do: Enum.reduce(then_c ++ else_c, acc, &walk/2)
  defp walk({:for, _var, _coll, children}, acc), do: Enum.reduce(children, acc, &walk/2)
  defp walk(_leaf, acc), do: acc

  defp elements(tree), do: tree |> walk([]) |> Enum.reverse()

  defp norm_value({:static, s}), do: {:text, s}

  defp norm_value({:parts, parts}) do
    case parts do
      [{:expr, e}] -> {:expr, e}
      _ -> {:text, Enum.map_join(parts, "", fn {:text, s} -> s end)}
    end
  end

  defp bool_attrs(tree) do
    for {:element, _tag, attrs, _ch} <- elements(tree),
        {:"$bool", name, value} <- attrs,
        do: {name, norm_value(value)}
  end

  defp slot_shapes(tree) do
    for {:element, "slot", attrs, children} <- elements(tree) do
      {Enum.map(attrs, fn {n, v} -> {n, norm_value(v)} end), children}
    end
  end

  describe "lexer selection" do
    test "reports the active lexer" do
      assert Template.lexer() in [:hologram, :minimal]
    end

    test "this suite runs against the hologram parser when the dep is present" do
      # pins the dual-lexer claim: root repo (hologram in deps) uses the
      # Hologram parser; spike_kit (no hologram) uses the minimal lexer and
      # asserts `lexer: :minimal` in its own suite.
      assert Template.lexer() == :hologram
    end
  end

  describe "lit-html emission" do
    test "wraps the fragment in one html`...` and interpolates state/attr reads" do
      js = render!(~S|<span class="label">{@label}</span><span class="count">{@count}</span>|)

      # (the Hologram lexer emits the inter-tag whitespace as a text node)
      assert js ==
               ~S|html`<span class="label">${__t(this.label)}</span> <span class="count">${__t(this.count)}</span>`|
    end

    test "static attributes pass through verbatim" do
      js = render!(~S|<button type="button" class="chip" data-cy="root">x</button>|)

      assert js =~ ~S|<button type="button" class="chip" data-cy="root">x</button>|
    end

    test "expression attributes become interpolations" do
      js = render!(~S|<li class="item" data-cy={@label}>{@count}</li>|)

      assert js =~ ~S|data-cy="${__t(this.label)}"|
    end

    test "$event bindings route at translated actions with a params map" do
      js =
        render!(~S|<button type="button" data-cy="inc" $click={:increment}>+</button>|)

      assert js =~ ~S|@click=${(ev) => this.__tesseraRunAction("increment", {}, ev)}|
    end

    test "if/else becomes a lit ternary over nested html`...` branches" do
      js = render!(~S|<span class="dot">{%if @selected}*{%else}&middot;{/if}</span>|)

      assert js ==
               ~S|html`<span class="dot">${(this.selected) ? html`*` : html`&middot;`}</span>`|
    end

    test "if without else renders the empty template in the false branch" do
      js = render!(~S|<span>{%if state.selected}on{/if}</span>|)

      assert js =~ ~S|${(state.selected) ? html`on` : html``}|
    end

    test "for loops bind the loop var for body and attribute expressions" do
      js =
        render!(
          ~S|<ul>{%for item <- @items}<li class="item" data-cy={item.id}>{item.name}</li>{/for}</ul>|
        )

      assert js =~
               ~S|${(this.items ?? []).map((item) => html`<li class="item" data-cy="${__t(item.id)}">${__t(item.name)}</li>`)}|
    end
  end

  describe "?attr boolean bindings (lit-parity 1c, T-03)" do
    test "expression binding emits ?name=${expr} — no quotes, no __t" do
      js = render!(~S|<div ?hidden={@selected}></div>|)
      assert js == ~S|html`<div ?hidden=${this.selected}></div>`|
    end

    test "bare ?attr is a static presence attribute" do
      js = render!("<div ?hidden></div>")
      assert js == ~S|html`<div hidden></div>`|
    end

    test "static quoted ?attr is a presence attribute" do
      js = render!(~S|<div ?hidden="hidden"></div>|)
      assert js == ~S|html`<div hidden></div>`|
    end

    test "mixed text/expression boolean values are rejected by name" do
      {:ok, tree} = Template.parse(~S|<div ?hidden="a{@selected}b"></div>|)

      error = assert_raise CompileError, fn -> Template.to_lit_render(tree, ctx()) end
      assert error.description =~ "?hidden" and error.description =~ "single {expr}"
    end

    test "both lexers produce the same $bool tokens (expression, bare, static)" do
      for markup <- [
            ~S|<div ?hidden={@selected}></div>|,
            "<div ?hidden></div>",
            ~S|<div ?hidden="x"></div>|
          ] do
        {:ok, holo_tree} = Template.parse(markup)

        assert bool_attrs(holo_tree) == bool_attrs(minimal_tree(markup)),
               "lexer divergence for #{markup}"
      end
    end

    test "both lexers render ?attr identically" do
      for markup <- [~S|<div ?hidden={@selected}></div>|, "<div ?hidden></div>"] do
        {:ok, holo_tree} = Template.parse(markup)

        assert Template.to_lit_render(holo_tree, ctx()) ==
                 Template.to_lit_render(minimal_tree(markup), ctx())
      end
    end
  end

  describe "directive lowering (lit-parity 1d, D-01/D-02/D-06/T-06)" do
    test "class_map in attribute position emits class=${classMap({...})} — unquoted, no __t" do
      js = render!(~S|<div class={class_map(%{selected: @selected, count: @count})}></div>|)

      assert js ==
               ~S|html`<div class=${classMap({selected: this.selected, count: this.count})}></div>`|
    end

    test "style_map keeps camelCase keys and quotes custom-property string keys" do
      js =
        render!(
          ~S|<div style={style_map(%{backgroundColor: @label, "--tsr-x-accent": @label})}></div>|
        )

      assert js ==
               ~S|html`<div style=${styleMap({backgroundColor: this.label, "--tsr-x-accent": this.label})}></div>`|
    end

    test "if_defined in attribute position emits unquoted, no __t" do
      js = render!(~S|<div title={if_defined(@label)}></div>|)
      assert js == ~S|html`<div title=${ifDefined(this.label)}></div>`|
    end

    test "nothing in attribute position emits unquoted (removes the attribute)" do
      js = render!(~S|<div title={nothing}></div>|)
      assert js == ~S|html`<div title=${nothing}></div>`|
    end

    test "nothing in child position emits ${nothing} without __t" do
      js = render!(~S|<div>{nothing}</div>|)
      assert js == ~S|html`<div>${nothing}</div>`|
    end

    test "class_map in child position emits the directive without __t" do
      js = render!(~S|<div>{class_map(%{selected: @selected})}</div>|)
      assert js == ~S|html`<div>${classMap({selected: this.selected})}</div>`|
    end

    test "a non-directive single expression attribute stays quoted and __t-wrapped" do
      js = render!(~S|<div title={@label}></div>|)
      assert js == ~S|html`<div title="${__t(this.label)}"></div>`|
    end

    test "both lexers render directive templates identically" do
      for markup <- [
            ~S|<div class={class_map(%{selected: @selected})}></div>|,
            ~S|<div style={style_map(%{backgroundColor: @label})}></div>|,
            ~S|<div title={if_defined(@label)}></div>|,
            ~S|<div title={nothing}>{nothing}</div>|
          ] do
        {:ok, holo_tree} = Template.parse(markup)

        assert Template.to_lit_render(holo_tree, ctx()) ==
                 Template.to_lit_render(minimal_tree(markup), ctx()),
               "lexer divergence for #{markup}"
      end
    end
  end

  describe "<slot> grammar (non-void, fallback content)" do
    test "explicit close tag parses (Hologram treats slot as void — pre-pass fixes it)" do
      assert {:ok, {:element, "div", [], [{:element, "slot", [], []}]}} =
               Template.parse("<div><slot></slot></div>")
    end

    test "fallback content is preserved" do
      assert {:ok, {:element, "div", [], [{:element, "slot", [], [text: "fb"]}]}} =
               Template.parse("<div><slot>fb</slot></div>")

      assert render!("<div><slot>fb</slot></div>") == ~S|html`<div><slot>fb</slot></div>`|
    end

    test "named slot with attributes and fallback" do
      js = render!(~S|<div><slot name="header">fallback</slot></div>|)
      assert js == ~S|html`<div><slot name="header">fallback</slot></div>`|
    end

    test "self-closing slot still works" do
      assert {:ok, {:element, "div", [], [{:element, "slot", [], []}]}} =
               Template.parse("<div><slot /></div>")
    end

    test "both lexers produce the same slot tokens (pair, fallback, self-closing)" do
      for markup <- [
            "<div><slot></slot></div>",
            "<div><slot>fb</slot></div>",
            "<div><slot /></div>",
            ~S|<div><slot name="x">fb</slot></div>|
          ] do
        {:ok, holo_tree} = Template.parse(markup)

        assert slot_shapes(holo_tree) == slot_shapes(minimal_tree(markup)),
               "lexer divergence for #{markup}"
      end
    end

    test "literal <slot> inside quoted values and expressions is not rewritten" do
      markup = ~S|<div title="a <slot> b" data-x={@label == "<slot>"}></div>|
      assert {:ok, tree} = Template.parse(markup)
      {:element, "div", attrs, []} = tree
      assert {"title", {:static, "a <slot> b"}} in attrs
    end

    test "the reserved placeholder tag is rejected under both lexers" do
      assert {:error, msg} = Template.parse("<tsrslot></tsrslot>")
      assert msg =~ "reserved"

      assert {:error, msg} = Template.minimal_lex("<tsrslot></tsrslot>")
      assert msg =~ "reserved"
    end
  end

  describe "grammar errors (each named)" do
    test "mismatched close tag" do
      assert {:error, msg} = Template.parse("<div><span></div>")
      assert msg =~ "no matching open tag"
    end

    test "unclosed block" do
      assert {:error, msg} = Template.parse("<div>{%if @selected}a</div>")
      assert msg =~ "no matching open tag"
    end

    test "unknown directive" do
      assert {:error, msg} = Template.parse("<div>{%unless @x}a{/unless}</div>")
      assert msg =~ "{%unless}" and msg =~ "supported directives"
    end

    test "component tags are rejected (plain DOM only)" do
      assert {:error, msg} = Template.parse("<Foo />")
      assert msg =~ "component tag <Foo>" and msg =~ "behaviors.add"
    end

    test "raw blocks are rejected" do
      assert {:error, msg} = Template.parse("{%raw}<b>x</b>{/raw}")
      assert msg =~ "{%raw}"
    end
  end

  describe "emit-time subset errors (raise as CompileError)" do
    test "$click={:undeclared} names the action" do
      {:ok, tree} = Template.parse(~S|<button $click={:nope}>x</button>|)

      error = assert_raise CompileError, fn -> Template.to_lit_render(tree, ctx()) end
      assert error.description =~ "action :nope"
    end

    test "interpolating an undeclared attr names it" do
      {:ok, tree} = Template.parse(~S|<span>{@nope}</span>|)

      error = assert_raise CompileError, fn -> Template.to_lit_render(tree, ctx()) end
      assert error.description =~ "does not resolve"
    end
  end

  # -- template regions (brief 2d, EXTENSION-CONTRACT.md §5.4) -------------------

  describe "region lexing (brief 2d, T1-1)" do
    test "region markup forces the minimal lexer on the hologram host" do
      if Template.lexer() == :hologram do
        assert Template.lexer_for(~S|<div>{%region :row}x{%endregion}</div>|) == :minimal
        # {%super%} alone also forces minimal
        assert Template.lexer_for(~S|<div>{%super%}</div>|) == :minimal
        # non-region markup keeps the host lexer
        assert Template.lexer_for(~S|<div>x</div>|) == Template.lexer()
      end
    end

    test "{%region :name} + {%endregion} lex to region tokens" do
      assert {:ok, [{:region_start, :row}, {:text, "x"}, :region_end]} =
               Template.minimal_lex("{%region :row}x{%endregion}")

      # endregion is NOT lexed as a {%region open tag
      assert {:ok, [:region_end]} = Template.minimal_lex("{%endregion}")
    end

    test "invalid region names are rejected by message" do
      assert {:error, msg} = Template.minimal_lex("{%region row}x{%endregion}")
      assert msg =~ "invalid {%region} name"

      assert {:error, msg} = Template.minimal_lex("{%region :Row}x{%endregion}")
      assert msg =~ "invalid {%region} name"

      assert {:error, msg} = Template.minimal_lex("{%region :row")
      assert msg =~ "unclosed {%region} tag"
    end

    test "region frames nest and treeify to {:region, name, children}" do
      assert {:ok, tree} =
               Template.minimal_lex(
                 "{%region :row}<li>{%region :cell}x{%endregion}</li>{%endregion}"
               )
               |> then(fn {:ok, tokens} -> Template.treeify(tokens, [], []) end)

      assert {:region, :row, [{:element, "li", [], [{:region, :cell, [text: "x"]}]}]} = tree
    end

    test "{%endregion} without a matching {%region} errors" do
      {:ok, tokens} = Template.minimal_lex("<div>{%endregion}</div>")
      assert {:error, msg} = Template.treeify(tokens, [], [])
      assert msg =~ "{%endregion} without a matching {%region}"
    end

    test "nesting is capped at 8 regions" do
      body = Enum.map_join(1..8, "", fn i -> "{%region :r#{i}}" end)
      close = String.duplicate("{%endregion}", 8)

      assert {:ok, _} = Template.parse("<div>#{body}x#{close}</div>")

      too_deep =
        Enum.map_join(1..9, "", fn i -> "{%region :r#{i}}" end) <>
          "x" <> String.duplicate("{%endregion}", 9)

      assert {:error, msg} = Template.parse("<div>#{too_deep}</div>")
      assert msg =~ "nest more than 8 regions deep"
    end
  end

  describe "region emission (method calls + super)" do
    test "a region in the host template lowers to a method call" do
      js = render!(~S|<ul><li class="row">{%region :row}<span>x</span>{%endregion}</li></ul>|)
      assert js =~ "${this.__region_row()}"
      refute js =~ "<span>x</span>"
    end

    test "compile_region_methods emits one html`…` body per region, preorder" do
      {:ok, tree} =
        Template.parse(
          ~S|<div>{%region :a}A{%region :b}B{%endregion}{%endregion}{%region :c}C{%endregion}</div>|
        )

      methods = Template.compile_region_methods(tree, ctx())
      assert Enum.map(methods, & &1.name) == [:a, :b, :c]
      assert Enum.map(methods, & &1.js) == ["html`A${this.__region_b()}`", "html`B`", "html`C`"]
    end

    test "duplicate region names raise a CompileError" do
      {:ok, tree} =
        Template.parse(~S|<div>{%region :x}a{%endregion}{%region :x}b{%endregion}</div>|)

      error = assert_raise CompileError, fn -> Template.compile_region_methods(tree, ctx()) end
      assert error.description =~ "duplicate template region"
    end

    test "regions/1 lists declared names with their nested sets" do
      {:ok, tree} =
        Template.parse(~S|<div>{%region :row}R{%region :cell}C{%endregion}{%endregion}</div>|)

      assert Template.regions(tree) == [
               %{name: :row, nested: [:cell]},
               %{name: :cell, nested: []}
             ]
    end

    test "{%super%} inside an override body lowers to super.__region_<name>()" do
      {:ok, body} = Template.parse(~S|<li class="v">{%super%}</li>|)
      ovr = Template.compile_region_override(:row, body, ctx())
      assert ovr.js == "html`<li class=\"v\">${super.__region_row()}</li>`"
    end

    test "{%super%} outside an override (default body / host template) raises" do
      {:ok, tree} = Template.parse(~S|<div>{%super%}</div>|)

      error = assert_raise CompileError, fn -> Template.to_lit_render(tree, ctx()) end
      assert error.description =~ "only valid inside a slot_template region override"

      {:ok, row} = Template.parse(~S|<div>{%region :x}{%super%}{%endregion}</div>|)
      assert_raise CompileError, fn -> Template.compile_region_methods(row, ctx()) end
    end

    test "regions may contain <slot> and $event bindings (compiled-in fragments, not DOM slots)" do
      js =
        render!(
          ~S|<div>{%region :row}<slot name="row-icon"></slot><button type="button" $click={:increment}>+</button>{%endregion}</div>|
        )

      assert js =~ "${this.__region_row()}"

      {:ok, tree} =
        Template.parse(~S|<div>{%region :row}<slot name="row-icon"></slot>{%endregion}</div>|)

      [method] = Template.compile_region_methods(tree, ctx())
      assert method.js == ~S|html`<slot name="row-icon"></slot>`|
    end
  end
end
