defmodule Tessera.TestFixtures.Conformance.Live do
  @moduledoc """
  `<tsr-conf-live>` — fixture for `live(expr)` on a property binding
  (`.value={live(@draft)}`, lit-parity #67, BoE need #3). The user edits the
  input (DOM value drifts from state); `:clear` sets `draft` to the SAME ""
  it already holds plus bumps `clears`, so the element re-renders. Only
  `live` compares against the live DOM value and resets the input. Exercised
  by `js/test/live.test.mjs`.
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-live", js: "conf_live.mjs"

  state(:draft, :string, default: "")
  state(:clears, :integer, default: 0)

  cy("conf-live-root")

  template(~TSR"""
  <div data-cy="conf-live-root">
    <input data-cy="conf-live-input" .value={live(@draft)} />
    <span data-cy="conf-live-clears">{@clears}</span>
  </div>
  """)

  action(:clear, fn state, _params -> %{state | draft: "", clears: state.clears + 1} end)
end
