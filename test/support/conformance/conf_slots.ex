defmodule Tessera.TestFixtures.Conformance.Slots do
  @moduledoc """
  `<tsr-conf-slots>` — conformance fixture for Tier-1 shadow-DOM slots
  (brief 4b case-fill; slot rendering landed via D-T1, fallback content via
  brief 1c's slot pre-pass).

  A default slot, a named `header` slot, and a named `fb` slot with fallback
  content, each in its own wrapper so a case can assert which light-DOM
  children land where and when fallback renders.

  The default slot carries the SD-04 `$slotchange` → `slot_changed` binding
  (brief 2f wires the Tier-1 side; Tier-2 routes the same action through the
  shim's data-tsr-slot-change attribute), so the fixture also carries one
  state key (`slot_changes`) — the empty-`static properties` regression the
  moduledoc used to co-pin now lives solely in codegen_test's inline specs.

  Cases: SD-01 (default slot accepts a light-DOM child), SD-02 (named slot
  routes `slot="header"` children), SD-03 (slot fallback renders when no child
  is slotted, and is replaced when one is), SD-04 (slotchange reaches the
  component through the `slot_changed` action).
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-slots", js: "conf_slots.mjs"

  slot("header")
  slot("fb")

  # SD-04 (brief 2f wires the Tier-1 side): native `slotchange` on the default
  # slot drives the `slot_changed` action; the state key camelizes to
  # `slotChanges` in the §6.2 snapshot, matching the shared case body and the
  # Tier-2 data-tsr-slot-change shim route.
  state(:slot_changes, :integer, default: 0)

  cy("conf-slots-root")

  template(~TSR"""
  <div data-cy="conf-slots-root">
    <div data-cy="conf-slots-default"><slot $slotchange={:slot_changed}></slot></div>
    <div data-cy="conf-slots-named"><slot name="header"></slot></div>
    <div data-cy="conf-slots-fallback"><slot name="fb">fallback-content</slot></div>
  </div>
  """)

  action :slot_changed, fn state, _params ->
    %{state | slot_changes: state.slot_changes + 1}
  end
end
