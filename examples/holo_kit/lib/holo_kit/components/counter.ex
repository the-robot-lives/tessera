defmodule HoloKit.Components.Counter do
  @moduledoc """
  Baseline demo component — an ordinary Hologram component.

  `<tsr-holo-counter label=".." step="..">`: props `label` (render-only)
  and `step` (copied to state at init because actions can't read props —
  the standard Hologram pattern), state `count`. Emits `count-change`
  carrying `%{count, delta}` (camelCased to `{count, delta}` on the wire).
  """

  use Hologram.Component

  prop :label, :string, default: "Count"
  prop :step, :integer, default: 1

  def init(props, component) do
    component
    |> HoloKit.Emit.mount(props)
    |> Hologram.Component.put_state(count: 0, step: Map.get(props, :step, 1))
  end

  def action(:increment, _params, component) do
    step = Map.get(component.state, :step, 1)
    count = Map.get(component.state, :count, 0) + step

    component
    |> Hologram.Component.put_state(count: count)
    |> HoloKit.Emit.emit(:count_changed, %{count: count, delta: step})
  end

  def action(:decrement, _params, component) do
    step = Map.get(component.state, :step, 1)
    count = Map.get(component.state, :count, 0) - step

    component
    |> Hologram.Component.put_state(count: count)
    |> HoloKit.Emit.emit(:count_changed, %{count: count, delta: -step})
  end

  def action(_other, _params, component), do: component

  def template do
    ~HOLO"""
    <div class="tsr-counter" data-cy="holo-counter-root">
      <span class="tsr-counter-label" data-cy="holo-counter-label">{@label}</span>
      <button type="button" data-cy="holo-counter-dec" $click={:decrement}>-</button>
      <span class="tsr-counter-count" data-cy="holo-counter-count">{@count}</span>
      <button type="button" data-cy="holo-counter-inc" $click={:increment}>+</button>
    </div>
    """
  end
end
