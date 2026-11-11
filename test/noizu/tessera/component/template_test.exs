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
end
