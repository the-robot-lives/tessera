defmodule Tessera.TestFixtures.Conformance.UnsafeGuard do
  @moduledoc """
  `<tsr-conf-unsafe-guard>` — fixture for `unsafe_html(expr)` (Lit
  `unsafeHTML`, lit-parity #71) and `guard([deps], expr)` (Lit `guard`,
  #66) — BoE need #4. `:bump_other` changes an UNRELATED state key, so a
  guarded body (which also reads `@other`) must stay STALE; `:set_note`
  changes the dependency. Exercised by `js/test/unsafe_guard.test.mjs`.
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-unsafe-guard", js: "conf_unsafe_guard.mjs"

  state(:markup, :string, default: "<em data-cy=\"conf-ug-em\">trusted</em>")
  state(:note, :string, default: "n0")
  state(:other, :integer, default: 0)

  cy("conf-ug-root")

  template(~TSR"""
  <div data-cy="conf-ug-root">
    <div data-cy="conf-ug-html">{unsafe_html(@markup)}</div>
    <div data-cy="conf-ug-guard">{guard([@note], "#{@note}:#{@other}")}</div>
    <span data-cy="conf-ug-other">{@other}</span>
  </div>
  """)

  action(:bump_other, fn state, _params -> %{state | other: state.other + 1} end)
  action(:set_note, fn state, params -> %{state | note: params["note"]} end)
end
