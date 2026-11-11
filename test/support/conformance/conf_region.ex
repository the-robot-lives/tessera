defmodule Tessera.TestFixtures.Conformance.RegionBase do
  @moduledoc """
  `<tsr-conf-region>` — conformance fixture for template regions
  (brief 2d, EXTENSION-CONTRACT.md §5.4; case X-17).

  Declares one region, `:row`, inside a `<li>` — a compiled-in fragment that
  lowers to a `__region_row()` method on the element class. The host render
  interpolates `${this.__region_row()}`; a derived component replaces the
  body via `slot_template :row` (see `RegionVendor`). Regions are NOT DOM
  slots — the body rides the bundle and may itself contain `<slot>`s.

  Compile-failure half of X-17 (unknown region → CompileError §5.7) is
  Elixir-side only, proven in
  `test/noizu/tessera/component/extension_test.exs`.
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-region", js: "conf_region.mjs"

  cy("conf-region-root")

  template(~TSR"""
  <div data-cy="conf-region-root"><ul><li class="row" data-cy="conf-region-row">{%region :row}<span data-cy="conf-region-body">base-row</span>{%endregion}</li></ul></div>
  """)
end
