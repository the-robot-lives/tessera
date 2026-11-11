defmodule SpikeKit.ToggleChip do
  @moduledoc """
  `<spike-toggle-chip>` — SPIKE component (`spike/elixir-to-lit`).

  Mirrors the persona-card selection shape with the element DSL: props in
  (attrs), local state (selected flag + click counter), and a
  `chip-select` CustomEvent whose detail map crosses the wire camelCased
  (`chipId`, `selected`) — the Hologram bridge snake-cases it back on
  Hologram hosts (`on_chip_select={:chose}` in a page template lands in
  the page action with `params.chip_id`).
  """

  use Noizu.Tessera.Component, tag: "spike-toggle-chip", js: "spike_toggle_chip.mjs"

  attr(:chip_id, :string, required: true)
  attr(:label, :string, required: true)

  state(:selected, :boolean, default: false)
  state(:clicks, :integer, default: 0)

  event("chip-select", detail: %{chip_id: :string, selected: :boolean})

  cy("spike-chip-root")

  template ~TSR"""
  <button type="button" class="chip" data-cy="spike-chip-root" $click={:toggle}>
    <span class="dot">{%if @selected}*{%else}&middot;{/if}</span>
    <span class="chip-label" data-cy="spike-chip-label">{@label}</span>
    <span class="badge" data-cy="spike-chip-clicks">{@clicks}</span>
  </button>
  """

  action :toggle, fn state, _params ->
    emit("chip-select", %{chip_id: @chip_id, selected: not state.selected})
    %{state | selected: not state.selected, clicks: state.clicks + 1}
  end
end
