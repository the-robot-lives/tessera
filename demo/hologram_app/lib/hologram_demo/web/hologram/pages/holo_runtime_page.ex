defmodule HologramDemo.Web.Hologram.Pages.HoloRuntimePage do
  @moduledoc """
  Tier 2 spike host: a Hologram page whose OWN runtime keeps running while
  standalone tessera elements (Hologram components compiled by
  `mix tessera.compile_component`) mount inside it.

  * `<tsr-holo-counter>` / `<tsr-holo-editable-list>` / `<fancy-list>` are
    plain unknown tags in this template — upgraded by the glue module
    (`holo_runtime_glue.js`, js_import'ed + `JS.call` in `init/3`, replayed
    client-side after mount).
  * Element emits cross the shadow boundary as composed CustomEvents and
    reach this page's actions through the standard `data-tsr-on` bridge
    (snake_cased detail keys) — the same contract as Tier 1 elements.
  * `<fancy-list>` is the compile-time extension (spike item A) running
    alongside the base element on the same page.
  * Client navigation (nav links) must keep working with the elements
    mounted — asserted by the e2e spec.
  """

  use Hologram.Page
  use Hologram.JS

  alias HologramDemo.Web.Hologram.Layouts.RootLayout

  js_import :loadHoloRuntime, from: "../components/holo_runtime_glue.js"

  route "/holo_runtime"
  layout RootLayout, page_title: "holo runtime demo"

  @planets [
    %{id: 1, name: "Mercury"},
    %{id: 2, name: "Venus"},
    %{id: 3, name: "Earth"},
    %{id: 4, name: "Mars"}
  ]

  def init(_params, page, server) do
    JS.call(:loadHoloRuntime, [])

    page =
      put_state(page,
        saved_name: "—",
        saved_index: -1,
        archived_id: 0,
        count: 0,
        planets_json: Jason.encode!(%{items: @planets})
      )

    {page, server}
  end

  # — page actions reached via the data-tsr-on bridge ————————

  def action(:saved, params, page) do
    put_state(page,
      saved_name: Map.get(params, :name, "?"),
      saved_index: Map.get(params, :index, -1)
    )
  end

  def action(:archived, %{item_id: id}, page) do
    put_state(page, archived_id: id)
  end

  def action(:counted, %{count: count}, page) do
    put_state(page, count: count)
  end

  def action(_other, _params, page), do: page

  def template do
    ~HOLO"""
    <h1 data-cy="hr-title">holo runtime demo (tier 2)</h1>

    <div class="panel" data-cy="panel-hr-counter">
      <h2>counter — standalone Hologram component element</h2>
      <p data-cy="hr-count">count-changed events: <strong data-cy="hr-count-value">{@count}</strong></p>
      <tsr-holo-counter label="pings" step="1" data-tsr-on="count-changed:counted@page"></tsr-holo-counter>
    </div>

    <div class="panel" data-cy="panel-hr-list">
      <h2>editable list — base element</h2>
      <p data-cy="hr-saved">
        saved: <strong data-cy="hr-saved-name">{@saved_name}</strong>
        (<span data-cy="hr-saved-index">{@saved_index}</span>)
      </p>
      <tsr-holo-editable-list
        title="Planets"
        tsr-props={@planets_json}
        data-tsr-on="item-saved:saved@page"
      ></tsr-holo-editable-list>
    </div>

    <div class="panel" data-cy="panel-hr-fancy">
      <h2>fancy list — compile-time extension (item A)</h2>
      <p data-cy="hr-archived">
        archived id: <strong data-cy="hr-archived-value">{@archived_id}</strong>
      </p>
      <fancy-list
        title="Fancy planets"
        tsr-props={@planets_json}
        data-tsr-on="item-saved:saved@page;item-archived:archived@page"
      ></fancy-list>
    </div>
    """
  end
end
