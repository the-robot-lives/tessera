defmodule Tessera.TestFixtures.PersonaCard do
  @moduledoc """
  Golden-fixture tessera component. Its compiled spec pins the generated
  contract module (`test/fixtures/persona_card.contract.generated.mjs`) and
  the CEM (`test/fixtures/persona_card.cem.json`). Decls every DSL entry kind
  so the goldens cover attrs (required/defaulted/boolean), json props,
  multiple events (detail keys, camel conversion), named slots and cy.
  """

  use Noizu.Tessera.Component, tag: "persona-card", js: "persona_card.mjs"

  attr(:display_name, :string, required: true)
  attr(:disabled, :boolean, default: false)

  prop :tag_list, :list, json: true, default: []
  prop :filters, :map, json: true, default: %{}
  prop :max_count, :integer, default: 10

  event("persona-select", detail: %{persona_id: :string, click_count: :integer})
  event("persona-hover", detail: %{hovered: :boolean})

  slot("header")
  slot("footer")
  css "--persona-card-accent", default: "#6366f1"
  part "select-button"
  cy("persona-card-root")

  # Styles DSL (spec-only component: flows to the manifest + CEM theming
  # declarations; no generated element). Two tag-scoped var() reads pin the
  # CEM cssProperties shape; the shared entry pins the manifest shape.
  styles([
    ~CSS"""
    :host {
      color: var(--tsr-persona-card-accent, #6cf);
      gap: var(--tsr-persona-card-gap, 4px);
    }
    """,
    {:shared, "./persona_card_shared.mjs"}
  ])
end
