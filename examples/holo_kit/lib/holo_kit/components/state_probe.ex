defmodule HoloKit.Components.StateProbe do
  @moduledoc """
  `<tsr-holo-state-probe>` — Tier-2 conformance fixture for the extension
  contract's state + action surface (EXTENSION-CONTRACT §6, brief 3d; the
  Hologram-component mirror of the Tier-1 `tsr-conf-state` fixture).

  Deliberately exercises the multi-word round-trip: state `selected_id` /
  `item_count` (camelCase projection `selectedId` / `itemCount`), action
  `select_item` (dispatchable as `selectItem`), param key `selected_id`.
  Emits `conf_state_ping` (`conf-state-ping` on the wire, camelCase detail)
  from `bump` — the same event the shared X-03 case already pins on Tier 1.

  NO catch-all `action/3` clause: dispatching an unknown name raises Hologram's
  boxed `%FunctionClauseError{}` for `action/3`, which the Tier-2 shim
  classifies into the §6.3 `unknown-action` result. Cases: X-05…X-11, X-20,
  X-03 on Tier 2.
  """

  use Hologram.Component

  prop :step, :integer, default: 1

  def init(props, component) do
    component
    |> HoloKit.Emit.mount(props)
    |> Hologram.Component.put_state(
      count: 0,
      step: Map.get(props, :step, 1),
      selected_id: "none",
      item_count: 0
    )
  end

  def action(:bump, params, component) do
    step = Map.get(component.state, :step, 1)
    delta = Map.get(params, :delta) || step
    count = Map.get(component.state, :count, 0) + delta

    component
    |> Hologram.Component.put_state(count: count)
    |> HoloKit.Emit.emit(:conf_state_ping, %{count: count, delta: delta})
  end

  # Changes TWO state keys in one transition — the X-06 one-event/changed-keys
  # assertion needs a multi-key transition.
  def action(:select_item, params, component) do
    selected_id = Map.get(params, :selected_id, "none")
    item_count = Map.get(component.state, :item_count, 0) + 1

    Hologram.Component.put_state(component, selected_id: selected_id, item_count: item_count)
  end

  def action(:set_step, params, component) do
    Hologram.Component.put_state(component, step: Map.get(params, :step, 1))
  end

  def template do
    ~HOLO"""
    <div class="tsr-state-probe" data-cy="conf-state-root">
      <button type="button" data-cy="conf-state-inc" $click={:bump}>+</button>
      <span class="tsr-state-probe-count" data-cy="conf-state-count">{@count}</span>
      <button type="button" data-cy="conf-state-select" $click={:select_item, selected_id: "click"}>select</button>
      <span class="tsr-state-probe-selected" data-cy="conf-state-selected">{@selected_id}</span>
      <span class="tsr-state-probe-items" data-cy="conf-state-item-count">{@item_count}</span>
    </div>
    """
  end
end
