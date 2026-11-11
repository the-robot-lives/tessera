defmodule SpikeKit.VendorCounter do
  @moduledoc """
  `<vendor-counter>` — fresh-tag derivation fixture (EXTENSION-CONTRACT.md §5,
  conformance X-16). Extends `SpikeKit.Counter` via the canonical
  `use Vendor.Element` macro: inherits the base spec, layers an additive
  attr/state/event, overrides `:increment` with a real down-call
  (`base_action/3` → ES `super`), adds a new action, and composes styles over
  the base. The base's generated artifacts are untouched.
  """

  use SpikeKit.Counter, tag: "vendor-counter", js: "vendor_counter.mjs"

  # Additive surface (§5.5) — new names append after the inherited entries.
  attr(:badge, :string, default: "")
  state(:extra, :integer, default: 0)
  event("vendor-ping", detail: %{count: :integer})

  cy("vendor-counter-root")

  template ~TSR"""
  <div class="vendor-counter" data-cy="vendor-counter-root">
    <span class="badge">{@badge}</span>
    <span class="count" data-cy="vendor-counter-count">{@count}</span>
    <span class="extra" data-cy="vendor-counter-extra">{@extra}</span>
    <button type="button" class="inc" data-cy="vendor-counter-inc" $click={:increment}>+</button>
    <button type="button" class="bump" data-cy="vendor-counter-bump" $click={:bump_extra}>bump</button>
  </div>
  """

  # Override: dispatch down to the vendor increment (ES super), then layer a
  # vendor-ping event and the additive `extra` counter on top.
  action :increment, fn state, params ->
    state = base_action(:increment, state, params)
    emit("vendor-ping", %{count: state.count})
    %{state | extra: state.extra + 1}
  end

  # New action — additive, no down-call (nothing below it).
  action :bump_extra, fn state, _params ->
    %{state | extra: state.extra + 1}
  end

  styles ~CSS":host { border: 1px solid var(--vendor-counter-accent, #6366f1); }"
end