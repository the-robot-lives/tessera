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
