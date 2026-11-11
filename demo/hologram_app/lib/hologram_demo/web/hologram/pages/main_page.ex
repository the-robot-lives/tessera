defmodule HologramDemo.Web.Hologram.Pages.MainPage do
  @moduledoc """
  Demo page exercising the integration scenarios from the Phase 1c brief:

  * (a) stateless `<PersonaCard on_persona_select={:chose}/>` → page action
  * (b) stateful `<PersonaCard cid="p1" on_persona_select={{:chose, target: "p1"}}/>`
        inside a wrapper component → card action → chained page confirmation
        (`:cid_confirmed` — proves the cid targeting without conflating the
        click's own routing)
  * (c) `<PersonaPicker>` re-emitting `persona-picked` → page action
  * (d) `behaviors.add` extension (EXTENDING.md §2), installed from a
        `js_import`-ed module via `EnrichedPanel` — see
        `Components/EnrichedPanel` + `Components/demo_behaviors.js`
  """

  use Hologram.Page

  alias HologramDemo.Web.Hologram.Components.EnrichedPanel
  alias HologramDemo.Web.Hologram.Components.PanelB
  alias HologramDemo.Web.Hologram.Layouts.RootLayout
  alias PersonaKit.PersonaCard
  alias PersonaKit.PersonaPicker

  route "/"
  layout RootLayout, page_title: "tessera demo — main"

  def init(_params, page, _server) do
    put_state(page,
      selected: "",
      click_count: 0,
      picked: "",
      cid_confirmed: "",
      personas: [
        %{id: "ada", name: "Ada Lovelace", tags: ["analyst", "engine"]},
        %{id: "grace", name: "Grace Hopper", tags: ["compiler", "navy"]},
        %{id: "alan", name: "Alan Turing", tags: ["machine"]}
      ]
    )
  end

  # — page-side landing zone for the tessera bridge dispatches ———

  def action(:chose, %{persona_id: persona_id, click_count: click_count}, page) do
    put_state(page, selected: persona_id, click_count: click_count)
  end

  def action(:pick, %{persona_id: persona_id}, page) do
    put_state(page, picked: persona_id)
  end

  # Chained by PersonaKit.PersonaCard's cid-targeted :chose (panel b) —
  # arriving here is the observable proof that the cid targeting worked.
  def action(:cid_confirmed, %{persona_id: persona_id}, page) do
    put_state(page, cid_confirmed: persona_id)
  end

  def action(_other, _params, page), do: page

  def template do
    ~HOLO"""
    <h1 data-cy="main-title">tessera demo — main page</h1>

    <div class="panel" data-cy="panel-a">
      <h2>(a) stateless card → page action</h2>
      <p data-cy="main-selected">selected: <strong>{@selected}</strong></p>
      <p data-cy="main-click-count">clicks: <strong>{@click_count}</strong></p>
      <PersonaCard
        display_name="Ada Lovelace"
        tagline="first programmer"
        tag_list={["engine", "loop"]}
        on_persona_select={:chose}
      />
    </div>

    <div class="panel" data-cy="panel-b">
      <h2>(b) stateful card (cid target) → card action</h2>
      <p data-cy="main-cid-confirmed">cid-confirmed: <strong>{@cid_confirmed}</strong></p>
      <PanelB />
    </div>

    <div class="panel" data-cy="panel-c">
      <h2>(c) picker re-emit → page action</h2>
      <p data-cy="main-picked">picked: <strong>{@picked}</strong></p>
      <PersonaPicker title="Pick a persona" personas={@personas} on_persona_picked={:pick} />
    </div>

    <div class="panel" data-cy="panel-d">
      <h2>(d) behaviors extension</h2>
      <EnrichedPanel cid="enriched" />
    </div>
    """
  end
end
