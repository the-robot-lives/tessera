defmodule Tessera.TestFixtures.Conformance.Light do
  @moduledoc """
  `<tsr-conf-light>` — fixture for `render_root: :light` (lit-parity row #96,
  BoE need #1). Renders into the element itself (no shadow root): one state
  key, a `$click` action that emits a contract event, and a style rule that
  targets the TAG (`:host` does not match in light DOM). Exercised by
  `js/test/light_dom.test.mjs`.
  """

  use Noizu.Tessera.Component,
    tag: "tsr-conf-light",
    js: "conf_light.mjs",
    render_root: :light

  state(:count, :integer, default: 0)

  event("conf-light-ping", detail: %{count: :integer})

  cy("conf-light-root")

  styles([
    ~CSS"""
    tsr-conf-light .light-count {
      color: rgb(1, 2, 3);
    }
    """
  ])

  template(~TSR"""
  <div data-cy="conf-light-root">
    <button type="button" data-cy="conf-light-inc" $click={:bump}>+</button>
    <span class="light-count" data-cy="conf-light-count">{@count}</span>
  </div>
  """)

  action(:bump, fn state, _params ->
    emit("conf-light-ping", %{count: state.count + 1})
    %{state | count: state.count + 1}
  end)
end
