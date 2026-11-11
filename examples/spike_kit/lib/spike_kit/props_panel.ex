defmodule SpikeKit.PropsPanel do
  @moduledoc """
  `<spike-props>` — property options + lifecycle hooks + `?attr` fixture
  (lit-parity brief 1c). Exercises, in one element:

    * `attribute: "data-label"` + `reflect: true` (C-02/C-09/C-10),
    * `attribute: false` on a state key, `:list` → Lit `Array` (C-06/#21),
    * `should_update` / `will_update` / `first_updated` / `updated`
      (C-13/C-15, LC-01…LC-04) — `changed` carries the OLD property values,
    * `?hidden={@hidden}` boolean attribute binding (T-03).

  The WTR suite `test/components/props_panel_test.mjs` asserts the C/T/LC
  conformance rows against the generated element.
  """

  use Noizu.Tessera.Component, tag: "spike-props", js: "spike_props.mjs"

  # Custom attribute name + reflection: the DOM attribute is data-label, and
  # property writes reflect back to it (C-09/C-10).
  attr(:label, :string, default: "Props", attribute: "data-label", reflect: true)
  attr(:tone, :string, default: "calm")
  attr(:count, :integer, default: 0)
  attr(:active, :boolean, default: false)
  # No map default: the Hologram adapter stringifies attr defaults into the
  # element markup, and String.Chars has no Map impl (pre-existing adapter
  # gap — JSON-encoding non-scalar defaults is a follow-up). The C-06 WTR
  # test sets the attribute explicitly.
  attr(:payload, :map)
  attr(:tags, :list, attribute: "data-tags", default: [])

  prop(:items, :list, default: [])

  state(:ticks, :integer, default: 0)
  state(:will_seen, :integer, default: 0)
  state(:hidden, :boolean, default: false)
  state(:frozen, :boolean, default: false, attribute: false)

  event("props-will", detail: %{ticks: :integer})
  event("props-updated", detail: %{ticks: :integer})
  event("props-first", detail: %{ticks: :integer})

  cy("spike-props-root")

  template ~TSR"""
  <div class="props" data-cy="spike-props-root">
    <span class="label" data-cy="spike-props-label">{@label}</span>
    <span class="ticks" data-cy="spike-props-ticks">{@ticks}</span>
    <span class="will" data-cy="spike-props-will">{@will_seen}</span>
    <span class="items" data-cy="spike-props-items">{Enum.count(@items)}</span>
    <span class="secret" data-cy="spike-props-secret" ?hidden={@hidden}>secret</span>
    <button type="button" data-cy="spike-props-tick" $click={:tick}>tick</button>
    <button type="button" data-cy="spike-props-hide" $click={:toggle_hidden}>hide</button>
    <button type="button" data-cy="spike-props-freeze" $click={:freeze}>freeze</button>
  </div>
  """

  action(:tick, fn state, _params -> %{state | ticks: state.ticks + 1} end)
  action(:toggle_hidden, fn state, _params -> %{state | hidden: not state.hidden} end)
  action(:freeze, fn state, _params -> %{state | frozen: true} end)

  # C-15: once frozen, shouldUpdate vetoes every further update (the property
  # still changes; the render does not).
  should_update(fn state, _changed -> not state.frozen end)

  # LC-01/LC-04: runs before render; `changed.ticks` is the OLD value
  # (undefined on the first update). The returned map exercises willUpdate's
  # state application (will_seen renders in the same pass).
  will_update(fn state, changed ->
    emit("props-will", %{ticks: changed.ticks})
    %{state | will_seen: state.will_seen + 1}
  end)

  # LC-03/C-13: fires exactly once, after the first render.
  first_updated(fn state, _changed -> emit("props-first", %{ticks: state.ticks}) end)

  # LC-02: fires after every rendered update.
  updated(fn state, _changed -> emit("props-updated", %{ticks: state.ticks}) end)
end