defmodule PersonaKit.PersonaCard do
  @moduledoc """
  `<persona-card>` — tessera example component.

  A card presenting one persona: `display-name`, an optional `tagline`, an
  optional `disabled` flag and a json `tag_list` prop (shipped through
  `tsr-props`). Emits the composed `persona-select` CustomEvent carrying
  `{ personaId, clickCount }` (CONTRACT.md §1 naming) when the card's
  select button is clicked.

  The module also demonstrates a component-level action: a **stateful
  instance** (`<PersonaCard cid="p1" on_persona_select={{:chose, target: "p1"}} />`)
  dispatches `:chose` at the component's `cid`, which lands in
  `action/3` below (CONTRACT.md §3 tuple form). Stateless instances never
  reach it — bind an atom (`on_persona_select={:chose}`) to route to the
  page instead.

  The DSL below is the contract source of truth. `mix compile` regenerates
  `persona_card.contract.generated.mjs` next to `persona_card.mjs` and (in
  Hologram apps) the render + bridge wiring in this module. See the tessera
  `docs/AUTHORING.md`.
  """

  use Noizu.Tessera.Component, tag: "persona-card", js: "persona_card.mjs"

  # DOM attributes (snake_case atoms; reach the DOM kebab-cased).
  attr(:display_name, :string, required: true)
  attr(:tagline, :string, default: "")
  attr(:disabled, :boolean, default: false)

  # JSON prop (camelCased DOM property, shipped through tsr-props).
  prop(:tag_list, :list, json: true, default: [])

  # CustomEvent emitted by the element; the Hologram binding prop is
  # on_persona_select (action :chose targets @page; {:chose, target: cid}
  # targets a component instance — see action/3 below).
  event("persona-select", detail: %{persona_id: :string, click_count: :integer})

  slot("default")
  slot("footer")
  cy("persona-card-root")

  @doc """
  Component-level action for cid-bearing instances: the demo binds
  `on_persona_select={{:chose, target: "p1"}}`, so the bridge dispatches
  `:chose` at THIS module with the event detail (keys already
  snake-cased by the bridge — CONTRACT.md §4). The state update drives a
  re-render of this component instance, which is how the e2e suite proves
  shadow-DOM internals survive a stateful re-render.

  Gated on Hologram: `put_state/2` comes from `Hologram.Component`, and a
  component package must still compile standalone (spec-only) for
  spec-only consumers (plain HTML / npm hosts).
  """
  if Noizu.Tessera.Hologram.Adapter.available?() do
    def action(:chose, %{persona_id: persona_id, click_count: click_count}, component) do
      put_state(component, selected: persona_id, click_count: click_count)
    end

    def action(_other, _params, component), do: component
  end
end
