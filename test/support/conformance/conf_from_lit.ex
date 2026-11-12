defmodule Tessera.TestFixtures.Conformance.FromLitPanel do
  @moduledoc """
  `<tsr-conf-from-lit-panel>` — TESSER-019: a component converted by
  `mix tessera.from_lit` from a real Lit 3 source
  (`test/fixtures/from_lit/dashboard_panel.ts`) and rendered LIVE by
  `js/test/from_lit_render.test.mjs`.

  The attr/prop/state surface below is the converter's mechanical output,
  unchanged (warnings: `rows` ships as a json prop, Lit attribute
  observation dropped). Per the from-lit workflow step 3, the render was
  ported into the element DSL: the stub template kept (ternary →
  `{if/2}`, keyed repeat → `{%for .., key: ..}`, `@click` → `$click`),
  `tick` promoted from the commented no-op stub to a real state action,
  and data-cy hooks added (conformance selector convention only — no wire
  surface). Asserts the converted element's DOM matches what the original
  Lit render produces: text, attributes, list order, click → state.
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-from-lit-panel", js: "conf_from_lit.mjs"

  # Lit: panelTitle
  attr(:panel_title, :string, default: "Overview")
  # reflect
  attr(:open, :boolean, default: true)

  prop(:rows, :list,
    json: true,
    default: [
      %{"id" => "r1", "label" => "Inbox"},
      %{"id" => "r2", "label" => "Sent"},
      %{"id" => "r3", "label" => "Drafts"}
    ]
  )

  # Lit: tickCount
  state(:tick_count, :integer, default: 0)

  cy("from-lit-panel-root")

  template(~TSR"""
  <section class="panel" data-cy="from-lit-panel-root">
    <h3 data-cy="from-lit-title">{@panel_title}</h3>
    <p class="mode" data-cy="from-lit-mode">{if(@open, do: "open", else: "closed")}</p>
    <ul data-cy="from-lit-list">{%for row <- @rows, key: row.id}<li data-id={row.id}>{row.label}</li>{/for}</ul>
    <button type="button" data-cy="from-lit-tick" $click={:tick}>tick</button>
    <span class="ticks" data-cy="from-lit-ticks">{@tick_count}</span>
  </section>
  """)

  # Lit handler `tick` — ported from the stub: increments reactive state.
  action(:tick, fn state, _params -> %{state | tick_count: state.tick_count + 1} end)
end
