defmodule Tessera.TestFixtures.Conformance.Repeat do
  @moduledoc """
  `<tsr-conf-repeat>` — fixture for the keyed loop
  `{%for row <- @rows, key: row.id}` → Lit `repeat` (lit-parity #63, BoE need
  #2). `:reverse` reorders the rows; with `repeat` the existing `<li>` nodes
  MOVE (identity kept) instead of being re-rendered in place. Exercised by
  `js/test/repeat.test.mjs`.
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-repeat", js: "conf_repeat.mjs"

  state(:rows, :list,
    default: [
      %{"id" => "a", "label" => "Alpha"},
      %{"id" => "b", "label" => "Beta"},
      %{"id" => "c", "label" => "Gamma"}
    ]
  )

  cy("conf-repeat-root")

  template(~TSR"""
  <ul data-cy="conf-repeat-root">{%for row <- @rows, key: row.id}<li data-id={row.id}>{row.label}</li>{/for}</ul>
  """)

  action(:reverse, fn state, _params -> %{state | rows: Enum.reverse(state.rows)} end)
end
