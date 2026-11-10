defmodule Noizu.Tessera.ComponentRenderTest do
  use ExUnit.Case, async: true

  alias Hologram.Server
  alias Hologram.Template.Renderer

  @fixture_mod Tessera.TestFixtures.PersonaCard

  # Renders the fixture component the way the renderer consumes pages: a
  # {:component, module, props_dom, children_dom} node. props_dom entries are
  # {snake_name, [expression: {value}]} (the pre-evaluated form the renderer's
  # cast_props/evaluate_prop_value accepts). %Renderer.Env{} + %Server{} are
  # the empty render contexts (no cid → stateless render, no init/3 call).
  defp render(props_dom, children_dom \\ [{:text, "kid"}]) do
    {html, registry, _server} =
      Renderer.render_dom(
        {:component, @fixture_mod, props_dom, children_dom},
        %Renderer.Env{},
        %Server{}
      )

    {html, registry}
  end

  test "renders kebab attrs, dropping nil and false (booleans by presence)" do
    {html, _} =
      render([
        {"display_name", [expression: {"Ada"}]},
        {"disabled", [expression: {false}]}
      ])

    assert html =~ "<persona-card"
    assert html =~ ~s(display-name="Ada")
    # false attr value → attribute removed entirely (CONTRACT.md §3)
    refute html =~ "disabled"

    {html, _} =
      render([{"display_name", [expression: {"Ada"}]}, {"disabled", [expression: {true}]}])

    assert html =~ "disabled"
  end

  test "renders tsr-props JSON with camelCase keys (entity-encoded by the server renderer)" do
    {html, _} =
      render([
        {"display_name", [expression: {"Ada"}]},
        {"tag_list", [expression: {["a", "b"]}]},
        {"max_count", [expression: {10}]}
      ])

    # The server renderer HTML-encodes interpolated attribute values; the DOM
    # decodes on getAttribute, so &quot; here is the encoded tsr-props JSON.
    assert html =~ "tsr-props="
    assert html =~ "&quot;"
    assert html =~ "&quot;tagList&quot;:[&quot;a&quot;,&quot;b&quot;]"
    # max_count is NOT json-flagged → stays out of tsr-props entirely
    refute html =~ "maxCount"
    # filters is not passed → its declared default is injected and shipped
    assert html =~ "&quot;filters&quot;:{}"
  end

  test "omits tsr-props when the spec has no json props" do
    {html, _registry, _server} =
      Renderer.render_dom(
        {:component, Tessera.TestFixtures.BareThing, [{"label", [expression: {"hi"}]}],
         [{:text, "kid"}]},
        %Renderer.Env{},
        %Server{}
      )

    refute html =~ "tsr-props"
  end

  test "renders data-tsr-on for bound events with page target" do
    {html, _} =
      render([
        {"display_name", [expression: {"Ada"}]},
        {"on_persona_select", [expression: {:chose}]},
        {"on_persona_hover", [expression: {{:hovered, []}}]}
      ])

    assert html =~ "data-tsr-on="
    # :action binds to @page; {:action, target: "layout"|cid} binds elsewhere;
    # entries joined with ";" in spec order
    assert html =~ "persona-select:chose@page;persona-hover:hovered@page"
  end

  test "renders layout and cid targets from {:action, target: ...} bindings" do
    {html, _} =
      render([
        {"display_name", [expression: {"Ada"}]},
        {"on_persona_select", [expression: {{:chose, target: "layout"}}]}
      ])

    assert html =~ "persona-select:chose@layout"

    {html, _} =
      render([
        {"display_name", [expression: {"Ada"}]},
        {"on_persona_select", [expression: {{:chose, target: "picker1"}}]}
      ])

    assert html =~ "persona-select:chose@picker1"
  end

  test "omits data-tsr-on when no event binding is passed" do
    {html, _} = render([{"display_name", [expression: {"Ada"}]}])
    refute html =~ "data-tsr-on"
  end

  test "renders data-cy" do
    {html, _} = render([{"display_name", [expression: {"Ada"}]}])
    assert html =~ ~s(data-cy="persona-card-root")
  end

  test "passes children through as slot content" do
    {html, _} = render([{"display_name", [expression: {"Ada"}]}], [{:text, "kid content"}])

    # <slot /> expands to the children
    assert html =~ "kid content"
    assert html =~ "</persona-card>"
  end

  test "stateless render never touches the component registry" do
    {_, registry} = render([{"display_name", [expression: {"Ada"}]}])
    assert registry == %{}
  end

  test "stateful render (cid prop) registers the component and runs init/3" do
    {html, registry} =
      render([
        {"display_name", [expression: {"Ada"}]},
        {"cid", [expression: {"c1"}]}
      ])

    assert html =~ "<persona-card"
    assert Map.has_key?(registry, "c1")
    assert registry["c1"].module == @fixture_mod
  end

  test "template markup is contract-shaped (structural assertions on the source)" do
    markup = Noizu.Tessera.Hologram.Adapter.template_markup(@fixture_mod.__tessera_spec__())

    expected = """
    <persona-card
      display-name={@display_name}
      disabled={@disabled}
      tsr-props={__tessera_props_json__(%{tag_list: @tag_list, filters: @filters})}
      data-tsr-on={__tessera_data_tsr_on__(%{on_persona_select: @on_persona_select, on_persona_hover: @on_persona_hover})}
      data-cy="persona-card-root"
    >
      <slot />
    </persona-card>
    """

    assert markup == String.trim_trailing(expected, "\n")
  end

  test "generated init/3 registers and defaults to a pass-through" do
    assert function_exported?(@fixture_mod, :init, 3)
    assert function_exported?(@fixture_mod, :__tessera_init__, 3)

    component = %Hologram.Component{}
    {component2, server2} = @fixture_mod.init(%{display_name: "Ada"}, component, %Server{})

    # default __tessera_init__ returns the component untouched
    assert component2 == component
    assert %Server{} = server2
  end
end
