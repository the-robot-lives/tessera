defmodule PersonaKit.PersonaPicker do
  @moduledoc """
  `<persona-picker>` — tessera example component.

  Composes several `<persona-card>` elements INSIDE its own shadow DOM and
  demonstrates the CONTRACT.md §4 / EXTENDING.md §4 nested-shadow pattern:
  the child cards' `persona-select` events stay private to the picker; the
  picker RE-EMITS them from itself as `persona-picked`
  (`{ personaId }`), so the host binds only the picker's own event:

      <PersonaPicker title="…" personas={@personas} on_persona_picked={:pick} />

  The personas prop is a json prop: a list of plain maps
  (`%{id: "ada", name: "Ada Lovelace", tags: ["logic", "math"]}` — keys are
  shipped verbatim through `tsr-props` JSON; the picker reads `name`/`id`/
  `tags` on the JS side).

  The DSL below is the contract source of truth. `mix compile` regenerates
  `persona_picker.contract.generated.mjs` next to `persona_picker.mjs`.
  """

  use Noizu.Tessera.Component, tag: "persona-picker", js: "persona_picker.mjs"

  attr(:title, :string, required: true)

  prop(:personas, :list, json: true, default: [])

  event("persona-picked", detail: %{persona_id: :string})

  slot("default")
  cy("persona-picker-root")
end
