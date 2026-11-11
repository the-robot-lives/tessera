defmodule HoloKit.Components.SlotProbe do
  @moduledoc """
  `<tsr-holo-slot-probe>` — Tier-2 conformance fixture for the shadow-DOM
  slot family (lit-parity §2.6 rows #107-#109, brief 3e; SD-01…SD-04 mount
  it on the Tier-2 Cypress adapter).

  Slot wiring mechanism: Hologram consumes `<slot>` markup at both ends
  (void-parse in the parser; the renderers replace a slot node with the
  slots passed INTO the component), so `<slot>` in a template NEVER becomes
  a DOM slot on Tier 2. The shim supplies the pass-through: any marker
  element carrying `data-tsr-slot` is rewritten at the vnode level into a
  real `<slot>` before the patch — `data-tsr-slot=""` is the default slot,
  `data-tsr-slot="name"` the named one, and because the marker is an
  ordinary element its children survive the parse as slot FALLBACK content
  (the one thing `<slot>` markup cannot express here — a void parse orphans
  it). `data-tsr-slot="fb"` + child text ⇒ `<slot name="fb">fallback…`.

  `#107` slotchange is NOT bindable with Hologram's `$event` syntax — the
  client runtime resolves event handlers through a hardcoded whitelist
  (`assets/js/hologram.mjs #getEventImplementation`) and `slotchange` is not
  in it (an unlisted type throws inside `handleUiEvent`). The shim routes it
  instead: `data-tsr-slot-change="record_slot_change"` attaches a native
  slotchange listener to the rewritten <slot> that dispatches the named
  action through the §6.3 pipeline. Every genuine assignment change runs the
  action, bumping state `slot_changes` (camelCase `slotChanges` on the §6.2
  snapshot) — SD-04 pins the transition.
  `#108/#109` (`assignedElements`/`assignedNodes`) are plain platform APIs
  on the resulting slot; the shared SD cases read them through the mount
  handle's shadowRoot.
  """

  use Hologram.Component

  def init(props, component) do
    component
    |> HoloKit.Emit.mount(props)
    |> Hologram.Component.put_state(slot_changes: 0)
  end

  def action(:record_slot_change, _params, component) do
    n = Map.get(component.state, :slot_changes, 0) + 1
    Hologram.Component.put_state(component, slot_changes: n)
  end

  def action(_other, _params, component), do: component

  def template do
    ~HOLO"""
    <div class="tsr-slot-probe" data-cy="conf-slots-root">
      <div data-cy="conf-slots-default"><span data-tsr-slot="" data-tsr-slot-change="record_slot_change"></span></div>
      <div data-cy="conf-slots-named"><span data-tsr-slot="header"></span></div>
      <div data-cy="conf-slots-fallback"><span data-tsr-slot="fb">fallback-content</span></div>
      <span class="tsr-slot-count" data-cy="conf-slots-count">{@slot_changes}</span>
    </div>
    """
  end

  def __tsr_actions__, do: [:record_slot_change]
end
