defmodule Tessera.TestFixtures.Conformance.State do
  @moduledoc """
  `<tsr-conf-state>` — conformance fixture for the Tier-1 element DSL's
  reactive-state core (brief 4b case-fill; feature landed via D-T1).

  One state key, one contract event, a `$click` action binding. The action
  emits `conf-state-ping` (composed + bubbling, camelCase detail) and returns
  the next state, which drives a reactive re-render of `{@count}`.

  Cases: C-07 (state reactivity re-renders), T-05 (`$click` invokes the
  handler), X-03 (contract events composed+bubbling, camelCase detail).
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-state", js: "conf_state.mjs"

  attr(:step, :integer, default: 1)

  state(:count, :integer, default: 0)

  event("conf-state-ping", detail: %{count: :integer, delta: :integer})

  cy("conf-state-root")

  template ~TSR"""
  <div data-cy="conf-state-root">
    <button type="button" data-cy="conf-state-inc" $click={:bump}>+</button>
    <span data-cy="conf-state-count">{@count}</span>
  </div>
  """

  action :bump, fn state, _params ->
    emit("conf-state-ping", %{count: state.count + @step, delta: @step})
    %{state | count: state.count + @step}
  end
end