defmodule SpikeKit.Counter do
  @moduledoc """
  `<spike-counter>` — SPIKE component (`spike/elixir-to-lit`).

  The whole element is defined in this file: one state key, one event, a
  `~TSR` template and two actions translated to JS at compile time. The
  generated `spike-counter.element.generated.mjs` (LitElement subclass)
  and `spike_counter.mjs` (js entry wrapper) are written by `mix compile`
  — there is no hand-written JS for this component.
  """

  use Noizu.Tessera.Component, tag: "spike-counter", js: "spike_counter.mjs"

  attr(:label, :string, default: "Count")
  attr(:step, :integer, default: 1)

  state(:count, :integer, default: 0)

  event("count-change", detail: %{count: :integer, delta: :integer})

  cy("spike-counter-root")

  template ~TSR"""
  <div class="counter" data-cy="spike-counter-root">
    <span class="label">{@label}</span>
    <button type="button" class="btn dec" data-cy="spike-counter-dec" $click={:decrement}>-</button>
    <span class="count" data-cy="spike-counter-count">{@count}</span>
    <button type="button" class="btn inc" data-cy="spike-counter-inc" $click={:increment}>+</button>
  </div>
  """

  # Restricted-subset actions: literals, state reads/updates, arithmetic,
  # emit/2. The two-statement body (emit, then next state) compiles to a JS
  # IIFE; the returned map drives the reactive property update.
  action :increment, fn state, _params ->
    emit("count-change", %{count: state.count + @step, delta: @step})
    %{state | count: state.count + @step}
  end

  action :decrement, fn state, _params ->
    emit("count-change", %{count: state.count - @step, delta: -@step})
    %{state | count: state.count - @step}
  end
end
