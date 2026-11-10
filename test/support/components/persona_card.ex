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
  cy("persona-card-root")
end
